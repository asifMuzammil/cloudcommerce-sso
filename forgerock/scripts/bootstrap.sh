#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Generates everything the ForgeOps DS + AM images expect from Kubernetes
# (cert-manager certs, K8s secrets, init-container volumes) so they can run
# on plain Docker Compose.
#
#   secrets/ca/                 dev CA (signs the DS TLS cert)
#   secrets/ds-ssl-keypair/     DS TLS cert      -> SSL_CERT_DIR
#   secrets/ds-master-keypair/  DS master key    -> MASTER_CERT_DIR
#   secrets/truststore/         CA cert          -> DS + AM truststore
#   secrets/opendj-passwords/   uid=admin / uid=monitor passwords
#   secrets/am/                 AM keystore.jceks + .storepass/.keypass
#   secrets/amster/             authorized_keys (public key only)
#   secrets/amster-client/      amster private key (stays OUT of containers)
#   data/ds-idrepo, data/ds-cts empty DS data dirs (setup runs on first start)
#   .env                        AM runtime secrets for docker compose
#
# DEV ONLY. In production these come from AWS Secrets Manager / SSM.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

AM_IMAGE=${AM_IMAGE:-us-docker.pkg.dev/forgeops-public/images/am:8.1.1-latest}
S=secrets
CONTAINER_UID=11111   # both DS and AM images run as uid 11111, gid 0

if [ -e "$S" ] || [ -e data ] || [ -e .env ]; then
  echo "secrets/, data/ or .env already exist. Remove them first to regenerate:"
  echo "  docker compose down -v && rm -rf secrets data .env   (needs: sudo for data/)"
  exit 1
fi

rand() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"; }

mkdir -p $S/{ca,ds-ssl-keypair,ds-master-keypair,truststore,opendj-passwords,am,amster,amster-client}
mkdir -p data/ds-idrepo data/ds-cts

echo "==> 1/6 Dev CA"
openssl req -x509 -newkey rsa:3072 -sha256 -days 365 -nodes \
  -keyout $S/ca/ca.key -out $S/ca/ca.crt \
  -subj "/CN=CloudCommerce Dev CA/O=CloudCommerce" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

echo "==> 2/6 DS TLS certificate (SAN: ds-idrepo, ds-cts, localhost)"
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout $S/ds-ssl-keypair/tls.key -out $S/ds-ssl-keypair/tls.csr \
  -subj "/CN=ds/O=CloudCommerce" 2>/dev/null
cat > $S/ds-ssl-keypair/ext.cnf << 'EXT'
subjectAltName=DNS:ds-idrepo,DNS:ds-cts,DNS:localhost
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
EXT
openssl x509 -req -in $S/ds-ssl-keypair/tls.csr -CA $S/ca/ca.crt -CAkey $S/ca/ca.key \
  -CAcreateserial -days 365 -sha256 -extfile $S/ds-ssl-keypair/ext.cnf \
  -out $S/ds-ssl-keypair/tls.crt 2>/dev/null
rm $S/ds-ssl-keypair/tls.csr $S/ds-ssl-keypair/ext.cnf
cp $S/ca/ca.crt $S/ds-ssl-keypair/ca.crt

echo "==> 3/6 DS master key pair (protects DS-generated symmetric keys)"
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout $S/ds-master-keypair/tls.key -out $S/ds-master-keypair/tls.csr \
  -subj "/CN=master-key/O=CloudCommerce" 2>/dev/null
openssl x509 -req -in $S/ds-master-keypair/tls.csr -CA $S/ca/ca.crt -CAkey $S/ca/ca.key \
  -CAcreateserial -days 365 -sha256 -out $S/ds-master-keypair/tls.crt 2>/dev/null
rm $S/ds-master-keypair/tls.csr
cp $S/ca/ca.crt $S/ds-master-keypair/ca.crt
cp $S/ca/ca.crt $S/truststore/ca.crt

echo "==> 4/6 DS admin/monitor passwords"
printf '%s' "$(rand 24)" > $S/opendj-passwords/dirmanager.pw
printf '%s' "$(rand 24)" > $S/opendj-passwords/monitor.pw

echo "==> 5/6 AM keystore (aliases referenced by AM's secret mappings)"
STOREPASS=$(rand 32)
KEYPASS=$(rand 32)
printf '%s' "$STOREPASS" > $S/am/.storepass
printf '%s' "$KEYPASS"   > $S/am/.keypass
# No Java on the host: borrow keytool from the AM image itself.
kt() {
  docker run --rm --user "$(id -u):$(id -g)" -v "$PWD/$S/am:/work" -w /work \
    --entrypoint keytool "$AM_IMAGE" "$@" -keystore keystore.jceks -storetype jceks -storepass "$STOREPASS"
}
keypair() { # alias keyalg size-or-curve sigalg
  local extra=(-keysize "$3"); [ "$2" = EC ] && extra=(-groupname "$3")
  kt -genkeypair -alias "$1" -keyalg "$2" "${extra[@]}" -sigalg "$4" -validity 365 \
     -dname "CN=$1,O=CloudCommerce" -keypass "$KEYPASS"
}
seckey() { kt -genseckey -alias "$1" -keyalg "$2" -keysize 256 -keypass "$KEYPASS"; }

keypair rsajwtsigningkey   RSA 2048       SHA256withRSA     # OIDC id_token RS256 signing
keypair test               RSA 2048       SHA256withRSA     # RSA encryption/decryption
keypair selfserviceenctest RSA 2048       SHA256withRSA     # remote consent encryption
keypair es256test          EC  secp256r1  SHA256withECDSA
keypair es384test          EC  secp384r1  SHA384withECDSA
keypair es512test          EC  secp521r1  SHA512withECDSA
seckey  hmacsigningtest    HmacSHA256                       # HS256 signing
seckey  directenctest      AES                              # direct JWE encryption
kt -list | grep -E 'Entry|entries'

echo "==> 6/6 Amster key pair + .env"
ssh-keygen -q -t rsa -b 4096 -m PEM -N "" -C amster -f $S/amster-client/id_rsa
cp $S/amster-client/id_rsa.pub $S/amster/authorized_keys

cat > .env << ENV
# Generated by scripts/bootstrap.sh - DO NOT COMMIT
AM_PASSWORDS_AMADMIN_CLEAR=$(rand 20)
# Fixed (not random per restart) so encrypted config values survive restarts
AM_ENCRYPTION_KEY=$(rand 32)
AM_AUTHENTICATION_SHARED_SECRET=$(rand 32 | base64)
AM_OIDC_CLIENT_SUBJECT_IDENTIFIER_HASH_SALT=$(rand 32)
ENV
chmod 600 .env

echo "==> Permissions: containers run as uid ${CONTAINER_UID}, gid 0"
# Secrets: owner = you, group = root(0) -> readable by the containers, not by "others".
# Data dirs: owned by the container user so DS can write its database.
# A throwaway root container does the chown/chgrp, so no sudo is needed.
docker run --rm --user 0 -v "$PWD:/w" --entrypoint sh "$AM_IMAGE" -c "
  chgrp -R 0 /w/$S && chmod -R g+rX,o-rwx /w/$S &&
  chown -R ${CONTAINER_UID}:0 /w/data && chmod -R 770 /w/data"

echo
echo "Done. amadmin password:  grep AM_PASSWORDS_AMADMIN_CLEAR .env"
echo "Next:                    docker compose up -d && docker compose logs -f"
