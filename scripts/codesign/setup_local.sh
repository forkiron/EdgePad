#!/bin/bash
# Create a stable self-signed code-signing cert for local EdgePad dev builds.
#
# Why this exists:
#   `codesign --sign -` (ad-hoc) produces a different code identity on every
#   build. macOS TCC keys Accessibility/Input-Monitoring grants by code
#   identity, so each rebuild forgets the grant and re-prompts.
#
#   Signing with a stable self-signed cert keeps the same identity across
#   builds, so the grant sticks until you delete the cert.
#
# Usage:
#   ./scripts/codesign/setup_local.sh    # run once
#   ./build.sh                           # picks up the cert automatically

set -euo pipefail

CERT_NAME="EdgePad Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ Cert '$CERT_NAME' already in login keychain. Nothing to do."
    exit 0
fi

echo "▸ Generating self-signed code-signing cert '$CERT_NAME'…"

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

cat > "$WORKDIR/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3
[ dn ]
CN = $CERT_NAME
[ v3 ]
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

openssl pkcs12 -export -passout pass: \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -name "$CERT_NAME" -out "$WORKDIR/cert.p12"

security import "$WORKDIR/cert.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo ""
echo "✓ Imported '$CERT_NAME' into login keychain."
echo ""
echo "  Next ./build.sh run will sign with this cert. macOS may ask once to"
echo "  allow codesign access to the private key — choose 'Always Allow'."
echo ""
echo "  After that, your Accessibility grant for EdgePad will persist across"
echo "  rebuilds. To reset: delete the cert in Keychain Access and re-run this."
