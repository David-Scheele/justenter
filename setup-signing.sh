#!/bin/zsh
# One-time setup: creates a stable local code-signing identity ("JustEnter Dev Signing")
# so macOS keeps microphone/Accessibility/Keychain grants across rebuilds.
# Ad-hoc signatures change on every build, which makes macOS treat each build as a new
# app and re-ask for every permission. A stable identity fixes that permanently.
#
# macOS will ask for your login password ONCE (to trust the new certificate).
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="JustEnter Dev Signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ Signing identity already installed"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
# -legacy: OpenSSL 3 defaults to a PKCS12 format the macOS keychain can't import
if openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass:justenter -name "$IDENTITY" 2>/dev/null; then
    :
else
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/identity.p12" -passout pass:justenter -name "$IDENTITY"
fi

security import "$TMP/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P justenter -T /usr/bin/codesign

echo "→ macOS will now ask for your login password to trust the certificate (one time)."
security add-trusted-cert -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"

echo "✓ Signing identity installed. Rebuild with ./build.sh — permission grants now survive rebuilds."
echo "  (The first build may show one 'codesign wants to use key' prompt — click Always Allow.)"
