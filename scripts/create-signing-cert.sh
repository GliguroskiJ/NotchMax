#!/bin/bash
# Vytvoří vlastní (self-signed) podpisový certifikát pro NotchMax a připraví hodnoty pro GitHub Secrets.
# Díky stabilnímu podpisu si macOS po aktualizaci pamatuje oprávnění (Kalendář, Automatizace…).
# Spusť na Macu: bash scripts/create-signing-cert.sh
set -euo pipefail

WORK="$(mktemp -d)"
cd "$WORK"
PW="$(/usr/bin/openssl rand -hex 16)"

cat > cs.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = NotchMax Self-Signed
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cs.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "NotchMax Self-Signed" -out NotchMax.p12 -passout "pass:$PW"
base64 -i NotchMax.p12 | tr -d '\n' | pbcopy

echo
echo "Hotovo. Teď ve svém repozitáři na GitHubu otevři Settings → Secrets and variables → Actions a přidej dva secrety:"
echo
echo "  1) MACOS_CERT_P12       = obsah schránky (base64 certifikátu, už je zkopírovaný, jen vlož)"
echo "  2) MACOS_CERT_PASSWORD  = $PW"
echo
echo "Soubor NotchMax.p12 můžeš zálohovat do správce hesel: $WORK/NotchMax.p12"
echo "Po prvním vydání s tímto podpisem povol oprávnění naposledy; další aktualizace je už zachovají."
