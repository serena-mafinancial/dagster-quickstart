from dagster import Definitions, load_assets_from_modules, EnvVar
from dagster_snowflake_pandas import SnowflakePandasIOManager


from . import assets
all_assets = load_assets_from_modules([assets])

defs = Definitions(
    assets=all_assets,
    sensors=[assets.check_for_updated_grist_tables],
    resources={
        "snowflake_demo_db_io_manager": SnowflakePandasIOManager(
            account=EnvVar("SNOWFLAKE_ACCOUNT"),  # required
            user=EnvVar("SNOWFLAKE_USER"),  # required
            password=EnvVar("SNOWFLAKE_PASSWORD"),  # password or private key required
            database="DEMO_DB",  # required
            warehouse=EnvVar("SNOWFLAKE_WAREHOUSE"),  # optional, defaults to default warehouse for the account
            schema="TEST",  # optional, defaults to PUBLIC
        )
    },
)