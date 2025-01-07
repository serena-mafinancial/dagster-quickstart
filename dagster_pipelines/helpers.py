import httpx
from httpx import ConnectTimeout, ReadTimeout
from tenacity import retry, stop_after_attempt, retry_if_exception_type, wait_exponential_jitter, wait_random_exponential, retry_if_exception

from dagster_pipelines.config import GRIST_API_KEY
@retry(
    retry=retry_if_exception_type(ConnectTimeout|ReadTimeout),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(max=3),
    reraise=True,
)
def get_grist_api_response(url):
    auth_header = {'Authorization' : f'Bearer {GRIST_API_KEY}', 'Content-Type': 'application/json'}
    response = httpx.get(url, timeout=30.0, headers=auth_header)
    # designed to error if the response is bad rather than handle & retry
    if response.status_code == httpx.codes.OK:
        return response
    else:
        response.raise_for_status()

