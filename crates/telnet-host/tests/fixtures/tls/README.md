# TLS test fixtures

These certificates and private keys are public test data. Never use them for a deployment.

The EC and RSA leaf certificates cover `localhost`, are signed by the test CA, and are valid from
2020-01-01 through 2120-01-01. Each chain contains its leaf followed by the CA. The matching private
keys exercise PKCS8, SEC1, and PKCS1 PEM loading. The CA private key is not retained.
