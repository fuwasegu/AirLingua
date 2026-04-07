#!/bin/bash
# Self-signed certificate for code signing AirLingua
# This certificate is used in CI to sign the app with a stable identity,
# so that macOS TCC (accessibility permissions) persists across updates.
#
# Usage:
#   ./scripts/create-signing-cert.sh
#
# Output:
#   ./AirLingua-signing.p12  — Import this into GitHub Secrets as SIGNING_CERT_P12 (base64)
#
# After running this script:
#   1. base64 -i AirLingua-signing.p12 | pbcopy
#   2. Go to GitHub repo → Settings → Secrets → New repository secret
#      - Name: SIGNING_CERT_P12
#      - Value: (paste from clipboard)
#   3. Add another secret:
#      - Name: SIGNING_CERT_PASSWORD
#      - Value: (the password you entered below)

set -euo pipefail

CERT_NAME="AirLingua Signing"
P12_FILE="AirLingua-signing.p12"

echo "=== Creating self-signed code signing certificate ==="
echo "Certificate name: $CERT_NAME"
echo ""

# Prompt for p12 password
read -s -p "Enter password for .p12 file: " P12_PASSWORD
echo ""
read -s -p "Confirm password: " P12_PASSWORD_CONFIRM
echo ""

if [ "$P12_PASSWORD" != "$P12_PASSWORD_CONFIRM" ]; then
  echo "Error: passwords do not match"
  exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Generate RSA key
openssl genrsa -out "$TMPDIR/key.pem" 2048 2>/dev/null

# Create certificate config for code signing
cat > "$TMPDIR/cert.conf" << EOF
[req]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no

[req_dn]
CN = $CERT_NAME
O = fuwasegu

[codesign_ext]
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:true
subjectKeyIdentifier = hash
EOF

# Create self-signed certificate (valid for 10 years)
openssl req -new -x509 \
  -key "$TMPDIR/key.pem" \
  -out "$TMPDIR/cert.pem" \
  -days 3650 \
  -config "$TMPDIR/cert.conf" \
  2>/dev/null

# Export as .p12 (include both private key and certificate as an identity)
openssl pkcs12 -export \
  -inkey "$TMPDIR/key.pem" \
  -in "$TMPDIR/cert.pem" \
  -name "$CERT_NAME" \
  -out "$P12_FILE" \
  -passout "pass:$P12_PASSWORD" \
  2>/dev/null

echo ""
echo "=== Done ==="
echo "Created: $P12_FILE"
echo ""
echo "Next steps:"
echo "  1. Copy base64 to clipboard:"
echo "     base64 -i $P12_FILE | pbcopy"
echo ""
echo "  2. Add GitHub Secrets (repo → Settings → Secrets and variables → Actions):"
echo "     SIGNING_CERT_P12     = (paste from clipboard)"
echo "     SIGNING_CERT_PASSWORD = (the password you just entered)"
echo ""
echo "  3. Delete the .p12 file (don't commit it):"
echo "     rm $P12_FILE"
