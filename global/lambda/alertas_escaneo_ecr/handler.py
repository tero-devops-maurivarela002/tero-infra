"""Lambda de seguridad de Tero (DEVOPS-46).

EventBridge la llama cada vez que ECR termina de escanear una imagen
("ECR Image Scan", escaneo básico en cada push). Si el escaneo encontró
vulnerabilidades con severidad en SEVERIDADES (por defecto CRITICAL y HIGH),
publica un aviso en el topic de SNS (TOPIC_ARN), que llega por mail.

El mail dice qué imagen es (repositorio, tag y digest), cuántas
vulnerabilidades hay por severidad y las primeras CVE, con el link a la
consola. Si no hay nada grave, solo deja una línea en el log.
"""
import json
import os

MAX_CVES = 10


def _clientes():
    # boto3 viene incluido en el runtime de Lambda; se importa acá para que
    # los tests puedan correr sin boto3 instalado (le pasan clientes falsos).
    import boto3

    return boto3.client("ecr"), boto3.client("sns")


def severidades_configuradas():
    valor = os.environ.get("SEVERIDADES", "CRITICAL,HIGH")
    return [s.strip().upper() for s in valor.split(",") if s.strip()]


def hallazgos_graves(conteos, severidades):
    """Devuelve {severidad: cantidad} solo con las severidades que importan."""
    return {s: conteos[s] for s in severidades if conteos.get(s, 0) > 0}


def primeras_cves(ecr, repositorio, digest, severidades, maximo=MAX_CVES):
    """Lista las CVE más graves del escaneo. Si falla, devuelve [] (el aviso sale igual)."""
    try:
        resp = ecr.describe_image_scan_findings(
            repositoryName=repositorio,
            imageId={"imageDigest": digest},
            maxResults=100,
        )
    except Exception as err:  # noqa: BLE001 - el aviso es más importante que el detalle
        print(json.dumps({"nivel": "warn", "msg": "no se pudo leer el detalle", "error": str(err)}))
        return []
    orden = {s: i for i, s in enumerate(severidades)}
    hallazgos = [
        h for h in resp.get("imageScanFindings", {}).get("findings", [])
        if h.get("severity") in orden
    ]
    hallazgos.sort(key=lambda h: orden[h["severity"]])
    return hallazgos[:maximo]


def armar_mensaje(detalle, graves, cves, region):
    repositorio = detalle["repository-name"]
    digest = detalle["image-digest"]
    tags = ", ".join(detalle.get("image-tags") or []) or "(sin tag)"
    link = (
        f"https://{region}.console.aws.amazon.com/ecr/repositories/private/"
        f"{detalle.get('aws-account', '')}/{repositorio}/_/image/{digest}/scan-results?region={region}"
    )
    lineas = [
        f"El escaneo de ECR encontró vulnerabilidades graves en {repositorio}:{tags}.",
        "",
        "Cantidad por severidad:",
        *[f"  - {sev}: {cant}" for sev, cant in graves.items()],
        "",
        f"Imagen: {repositorio}@{digest}",
        f"Resultado completo: {link}",
    ]
    if cves:
        lineas += ["", f"Primeras {len(cves)}:"]
        for h in cves:
            paquete = {a["key"]: a["value"] for a in h.get("attributes", [])}
            nombre = paquete.get("package_name", "?")
            version = paquete.get("package_version", "?")
            lineas.append(f"  - [{h['severity']}] {h.get('name', '?')} en {nombre} {version}")
    lineas += [
        "",
        "Qué hacer: docs/seguridad/alertas-escaneo-ecr.md (tero-infra). Esta imagen",
        "no debería promoverse a test ni a prod hasta corregir o justificar los hallazgos.",
    ]
    asunto = f"[tero] {repositorio}:{tags}: " + ", ".join(f"{c} {s}" for s, c in graves.items())
    return asunto[:100], "\n".join(lineas)


def handler(event, context, ecr=None, sns=None):
    detalle = event.get("detail", {})
    repositorio = detalle.get("repository-name", "?")
    if detalle.get("scan-status") != "COMPLETE":
        print(json.dumps({"nivel": "info", "msg": "escaneo no completo", "repositorio": repositorio,
                          "estado": detalle.get("scan-status")}))
        return {"avisado": False, "motivo": "escaneo no completo"}

    severidades = severidades_configuradas()
    graves = hallazgos_graves(detalle.get("finding-severity-counts") or {}, severidades)
    if not graves:
        print(json.dumps({"nivel": "info", "msg": "sin vulnerabilidades graves", "repositorio": repositorio,
                          "conteos": detalle.get("finding-severity-counts") or {}}))
        return {"avisado": False, "motivo": "sin vulnerabilidades graves"}

    if ecr is None or sns is None:
        ecr, sns = _clientes()
    region = event.get("region") or os.environ.get("AWS_REGION", "us-east-1")
    detalle.setdefault("aws-account", event.get("account", ""))
    cves = primeras_cves(ecr, repositorio, detalle["image-digest"], severidades)
    asunto, mensaje = armar_mensaje(detalle, graves, cves, region)
    sns.publish(TopicArn=os.environ["TOPIC_ARN"], Subject=asunto, Message=mensaje)
    print(json.dumps({"nivel": "warn", "msg": "aviso enviado", "repositorio": repositorio, "graves": graves}))
    return {"avisado": True, "graves": graves}
