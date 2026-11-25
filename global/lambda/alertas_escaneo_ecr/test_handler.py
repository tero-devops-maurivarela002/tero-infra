"""Tests de la Lambda (DEVOPS-46). Corren sin AWS ni boto3:
python3 -m unittest discover -s global/lambda/alertas_escaneo_ecr
"""
import os
import unittest

import handler

EVENTO = {
    "account": "123456789012",
    "region": "us-east-1",
    "detail-type": "ECR Image Scan",
    "source": "aws.ecr",
    "detail": {
        "scan-status": "COMPLETE",
        "repository-name": "tero/ui",
        "image-digest": "sha256:abc",
        "image-tags": ["f733dee"],
        "finding-severity-counts": {"CRITICAL": 1, "HIGH": 3, "MEDIUM": 7},
    },
}


class EcrFalso:
    def __init__(self, falla=False):
        self.falla = falla

    def describe_image_scan_findings(self, **kwargs):
        if self.falla:
            raise RuntimeError("AccessDenied")
        return {"imageScanFindings": {"findings": [
            {"name": "CVE-2", "severity": "HIGH",
             "attributes": [{"key": "package_name", "value": "openssl"}, {"key": "package_version", "value": "3.0.1"}]},
            {"name": "CVE-3", "severity": "MEDIUM", "attributes": []},
            {"name": "CVE-1", "severity": "CRITICAL",
             "attributes": [{"key": "package_name", "value": "zlib"}, {"key": "package_version", "value": "1.2"}]},
        ]}}


class SnsFalso:
    def __init__(self):
        self.publicados = []

    def publish(self, **kwargs):
        self.publicados.append(kwargs)


def evento(**cambios):
    e = {**EVENTO, "detail": {**EVENTO["detail"], **cambios}}
    return e


class TestHandler(unittest.TestCase):
    def setUp(self):
        os.environ["TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:tero-seguridad"
        os.environ.pop("SEVERIDADES", None)

    def test_avisa_si_hay_critical_o_high(self):
        sns = SnsFalso()
        r = handler.handler(evento(), None, ecr=EcrFalso(), sns=sns)
        self.assertTrue(r["avisado"])
        self.assertEqual(r["graves"], {"CRITICAL": 1, "HIGH": 3})
        msg = sns.publicados[0]
        self.assertEqual(msg["TopicArn"], os.environ["TOPIC_ARN"])
        self.assertIn("tero/ui:f733dee", msg["Subject"])
        self.assertLessEqual(len(msg["Subject"]), 100)
        # CRITICAL primero, y MEDIUM no aparece en el detalle
        self.assertLess(msg["Message"].index("CVE-1"), msg["Message"].index("CVE-2"))
        self.assertNotIn("CVE-3", msg["Message"])
        self.assertIn("openssl 3.0.1", msg["Message"])

    def test_no_avisa_si_solo_hay_medium(self):
        sns = SnsFalso()
        r = handler.handler(evento(**{"finding-severity-counts": {"MEDIUM": 4, "LOW": 2}}), None,
                            ecr=EcrFalso(), sns=sns)
        self.assertFalse(r["avisado"])
        self.assertEqual(sns.publicados, [])

    def test_no_avisa_si_el_escaneo_fallo(self):
        sns = SnsFalso()
        r = handler.handler(evento(**{"scan-status": "FAILED"}), None, ecr=EcrFalso(), sns=sns)
        self.assertFalse(r["avisado"])
        self.assertEqual(sns.publicados, [])

    def test_avisa_aunque_no_pueda_leer_el_detalle(self):
        sns = SnsFalso()
        r = handler.handler(evento(), None, ecr=EcrFalso(falla=True), sns=sns)
        self.assertTrue(r["avisado"])
        self.assertIn("CRITICAL: 1", sns.publicados[0]["Message"])

    def test_severidades_configurables(self):
        os.environ["SEVERIDADES"] = "CRITICAL"
        sns = SnsFalso()
        r = handler.handler(evento(**{"finding-severity-counts": {"HIGH": 5}}), None, ecr=EcrFalso(), sns=sns)
        self.assertFalse(r["avisado"])


if __name__ == "__main__":
    unittest.main()
