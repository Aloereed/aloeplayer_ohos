# Local TLS test fixture

The private key in this directory is deliberately public test data. It is used only by temporary loopback HTTPS servers in tests and must never be installed on a real service. The certificate covers localhost / 127.0.0.1, is self-signed, and is not trusted by the application or system by default.

Regenerate all three files together with `tool/generate_tls_test_fixture.py` using the test Python environment with cryptography installed. Tests read the generated fingerprint rather than trusting this certificate globally.
