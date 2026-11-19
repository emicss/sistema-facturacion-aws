import os
import urllib.request
import boto3

API_NAME = os.getenv("APIGW_NAME", "facturacion-cloud-api")
REGION = os.getenv("AWS_REGION", "us-east-1")

def obtener_ip_publica_ec2() -> str:
    """Obtiene la IP pública actual de esta EC2 usando IMDSv2."""
    req_token = urllib.request.Request(
        "http://169.254.169.254/latest/api/token",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        method="PUT",
    )
    token = urllib.request.urlopen(req_token, timeout=3).read().decode()
    req_ip = urllib.request.Request(
        "http://169.254.169.254/latest/meta-data/public-ipv4",
        headers={"X-aws-ec2-metadata-token": token},
    )
    return urllib.request.urlopen(req_ip, timeout=3).read().decode().strip()

def actualizar_integraciones():
    ip_actual = obtener_ip_publica_ec2()
    client = boto3.client("apigatewayv2", region_name=REGION)

    apis = client.get_apis().get("Items", [])
    api = next((a for a in apis if a["Name"] == API_NAME), None)
    if not api:
        print(f"No se encontró la API '{API_NAME}' en API Gateway ({REGION}).")
        return

    api_id = api["ApiId"]
    integraciones = client.get_integrations(ApiId=api_id).get("Items", [])

    for integ in integraciones:
        uri_vieja = integ.get("IntegrationUri", "")
        nueva_uri = f"http://{ip_actual}:8000/{{proxy}}" if "{proxy}" in uri_vieja else f"http://{ip_actual}:8000/"
        client.update_integration(
            ApiId=api_id,
            IntegrationId=integ["IntegrationId"],
            IntegrationUri=nueva_uri,
        )
        print(f"Integración {integ['IntegrationId']} actualizada -> {nueva_uri}")

    print(f"Listo. Tu URL fija de API Gateway sigue siendo: {api['ApiEndpoint']}")

if __name__ == "__main__":
    actualizar_integraciones()
