"""Generate a public, localhost-only TLS fixture; never use its key in production."""
from datetime import datetime, timezone
from pathlib import Path
import ipaddress
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

root = Path(__file__).resolve().parents[1] / 'test' / 'fixtures' / 'tls'
root.mkdir(parents=True, exist_ok=True)
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'AloePlayer localhost test ONLY')])
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
    .public_key(key.public_key()).serial_number(x509.random_serial_number())
    .not_valid_before(datetime(2020, 1, 1, tzinfo=timezone.utc))
    .not_valid_after(datetime(2040, 1, 1, tzinfo=timezone.utc))
    .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost'),
        x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), critical=False)
    .sign(key, hashes.SHA256()))
(root / 'localhost-cert.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
(root / 'localhost-test-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
(root / 'sha256.txt').write_text(cert.fingerprint(hashes.SHA256()).hex(), encoding='ascii')
print('Generated localhost-only test certificate and public fixture key.')
