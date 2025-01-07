import json
import requests
import pandas as pd
import polars as pl
from datetime import datetime

from dagster import (
    Config,
    MaterializeResult,
    MetadataValue,
    asset,
    sensor,
    RunRequest,
    SkipReason,
    AssetSelection,
    AssetKey,
    SensorEvaluationContext,
    SensorResult,
    AssetMaterialization,
    DagsterInstance,
)

from dagster_pipelines.helpers import get_grist_api_response


class HNStoriesConfig(Config):
    top_stories_limit: int = 10
    hn_top_story_ids_path: str = "hackernews_top_story_ids.json"
    hn_top_stories_path: str = "hackernews_top_stories.csv"


@asset
def hackernews_top_story_ids(config: HNStoriesConfig):
    """Get top stories from the HackerNews top stories endpoint."""
    top_story_ids = requests.get("https://hacker-news.firebaseio.com/v0/topstories.json").json()

    with open(config.hn_top_story_ids_path, "w") as f:
        json.dump(top_story_ids[: config.top_stories_limit], f)


@asset(deps=[hackernews_top_story_ids])
def hackernews_top_stories(config: HNStoriesConfig) -> MaterializeResult:
    """Get items based on story ids from the HackerNews items endpoint."""
    with open(config.hn_top_story_ids_path, "r") as f:
        hackernews_top_story_ids = json.load(f)

    results = []
    for item_id in hackernews_top_story_ids:
        item = requests.get(f"https://hacker-news.firebaseio.com/v0/item/{item_id}.json").json()
        results.append(item)

    df = pd.DataFrame(results)
    df.to_csv(config.hn_top_stories_path)

    return MaterializeResult(
        metadata={
            "num_records": len(df),
            "preview": MetadataValue.md(str(df[["title", "by", "url"]].to_markdown())),
        }
    )

# Define the asset key as a constant
CASHFLOW_ASSUMPTIONS_KEY = AssetKey(["rec_assumptions", "test_cashflow_assumptions"])

@asset(
    key=CASHFLOW_ASSUMPTIONS_KEY,
    io_manager_key="snowflake_demo_db_io_manager"  # Explicitly specify the Snowflake IO manager
)
def test_cashflow_assumptions(
    context
) -> pd.DataFrame:
    """Asset that loads cashflow assumptions from Grist and materializes to Snowflake."""
    BASE_URL = 'https://mafinancial.getgrist.com/api/docs/'
    DOC_ID = "wQnGTtHUrW15ezHTm999bv"
    TABLE_ID = 'TestCashflowAssumptions'
    
    doc_response = get_grist_api_response(f'{BASE_URL}{DOC_ID}')
    grist_last_updated = datetime.strptime(doc_response.json()['updatedAt'], "%Y-%m-%dT%H:%M:%S.%fZ")

    records = get_grist_api_response(f'{BASE_URL}{DOC_ID}/tables/{TABLE_ID}/records')
    
    recs = records.json()['records']
    fields = [list(rec['fields'].values()) for rec in recs]
    cols = list(recs[0]['fields'].keys())
    df = pl.DataFrame(fields, schema=cols)

    # add date metadata
    df = df.with_columns(
        pl.lit(grist_last_updated).alias('grist_last_updated'),
        pl.lit(datetime.now()).alias('table_last_updated')
    )
    # ic(df)
    # convert to pandas
    df_pd = df.to_pandas()
    # ic(df_pd)
    return df_pd

# Define the list of assets to watch
grist_assets = [CASHFLOW_ASSUMPTIONS_KEY]

@sensor(
    minimum_interval_seconds=20,
    asset_selection=AssetSelection.keys(*grist_assets)
)
def check_for_updated_grist_tables(context):
    BASE_URL = 'https://mafinancial.getgrist.com/api/docs/'
    docs = [
        {"grist_name": "Cashflow Assumption", "doc_id": "wQnGTtHUrW15ezHTm999bv", "asset_keys": [CASHFLOW_ASSUMPTIONS_KEY]}
    ]

    cursor = json.loads(context.cursor) if context.cursor else {}
    newcursor = {}
    runrequests = []

    for doc in docs:
        api_url = f'{BASE_URL}{doc["doc_id"]}'
        response = get_grist_api_response(api_url)
        table_last_modified = response.json()['updatedAt']

        last_run_time = datetime.strptime(cursor[doc['grist_name']], "%Y-%m-%dT%H:%M:%S.%fZ") if doc['grist_name'] in cursor else datetime(1970, 1, 1)

        if datetime.strptime(table_last_modified, "%Y-%m-%dT%H:%M:%S.%fZ") > last_run_time:
            newcursor[doc['grist_name']] = table_last_modified
            
            # The fix is here - don't create new AssetKey objects, use the existing ones
            for asset_key in doc['asset_keys']:
                runrequests.append(
                    RunRequest(
                        run_key=f'{doc["grist_name"]}|{table_last_modified}',
                        asset_selection=[asset_key]  # Use the asset_key directly, don't wrap it in AssetKey()
                    )
                )
        else:
            newcursor[doc['grist_name']] = cursor[doc['grist_name']]
            
    if newcursor == cursor:
        return SkipReason("Table not updated since last run")
    else:
        context.update_cursor(json.dumps(newcursor))
        return runrequests