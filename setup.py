from setuptools import find_packages, setup

setup(
    name="dagster_pipelines",
    packages=find_packages(exclude=["dagster_pipelines_tests"]),
    install_requires=[
        "dagster",
        "dagster-snowflake-pandas",
        "dagster-snowflake",
        "dagster-cloud",
        "dagster-aws",
        "dagster-postgres",
        "psycopg2-binary",
        "dagster-webserver",
        "dagster-graphql",
        "pandas==2.2.3",
        "polars==1.17.1",
        "requests",
        "httpx",
        "tenacity",
    ],
    extras_require={"dev": ["dagster-webserver", "pytest"]},
)
