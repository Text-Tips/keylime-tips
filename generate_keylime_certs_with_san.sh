#!/bin/bash
# Script to generate Keylime certificates with SANs using OpenSSL
# This creates a complete CA infrastructure with proper SANs

set -e  # Exit on error

CA_DIR="/var/lib/keylime/reg_ca"

echo "==> Generating Keylime CA and certificates with SANs in $CA_DIR"

# Create or clean the CA directory
if [ -d "$CA_DIR" ]; then
    echo "WARNING: $CA_DIR exists. This script will overwrite existing certificates."
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

mkdir -p "$CA_DIR"
cd "$CA_DIR"

# ============================================
# Generate CA certificate
# ============================================
echo "==> Creating Certificate Authority (CA)"

# Create CA configuration
cat > ca.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = MA
L = Lexington
O = MITLL
OU = 53
CN = Keylime Certificate Authority

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

# Generate CA private key (unencrypted for scripting)
openssl genrsa -out cakey.pem 2048 2>/dev/null

# Generate CA certificate
openssl req -new -x509 -key cakey.pem -out cacert.crt -days 3650 -config ca.cnf

echo "✓ CA certificate created"

# Set CA key variable for certificate signing
CA_KEY="cakey.pem"

# ============================================
# Generate SERVER certificate with SANs
# ============================================
echo "==> Generating server certificate with SANs (localhost, 127.0.0.1, server)"

cat > server_san.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = MA
L = Lexington
O = MITLL
OU = 53
CN = server

[v3_req]
basicConstraints = CA:FALSE
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"

[alt_names]
DNS.1 = server
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Generate server key
openssl genrsa -out server-private.pem 2048 2>/dev/null

# Generate CSR with SANs
openssl req -new -key server-private.pem -out server.csr -config server_san.cnf

# Sign with CA private key
openssl x509 -req -in server.csr \
    -CA cacert.crt \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out server-cert.crt \
    -days 365 \
    -sha256 \
    -extensions v3_req \
    -extfile server_san.cnf

# Generate public key
openssl rsa -in server-private.pem -pubout -out server-public.pem 2>/dev/null

# Clean up
rm -f server.csr server_san.cnf

echo "✓ Server certificate created with SANs: server, localhost, 127.0.0.1"

# ============================================
# Generate CLIENT certificate with SANs
# ============================================
echo "==> Generating client certificate with SANs"

cat > client_san.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = MA
L = Lexington
O = MITLL
OU = 53
CN = client

[v3_req]
basicConstraints = CA:FALSE
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = clientAuth
subjectAltName = @alt_names
nsCertType = client
nsComment = "OpenSSL Generated Client Certificate"

[alt_names]
DNS.1 = client
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Generate client key
openssl genrsa -out client-private.pem 2048 2>/dev/null

# Generate CSR with SANs
openssl req -new -key client-private.pem -out client.csr -config client_san.cnf

# Sign with CA private key
openssl x509 -req -in client.csr \
    -CA cacert.crt \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out client-cert.crt \
    -days 365 \
    -sha256 \
    -extensions v3_req \
    -extfile client_san.cnf

# Generate public key
openssl rsa -in client-private.pem -pubout -out client-public.pem 2>/dev/null

# Clean up
rm -f client.csr client_san.cnf

echo "✓ Client certificate created with SANs: client, localhost, 127.0.0.1"

# ============================================
# Verify certificates
# ============================================
echo ""
echo "==> Verifying certificates..."

# Verify server cert
openssl verify -CAfile cacert.crt server-cert.crt
echo "✓ Server certificate chain verified"

# Verify client cert
openssl verify -CAfile cacert.crt client-cert.crt
echo "✓ Client certificate chain verified"

echo ""
echo "==> Displaying server certificate SANs:"
openssl x509 -in server-cert.crt -text -noout | grep -A 3 "Subject Alternative Name"

echo ""
echo "==> Displaying client certificate SANs:"
openssl x509 -in client-cert.crt -text -noout | grep -A 3 "Subject Alternative Name"

# Clean up temporary config files
rm -f ca.cnf

echo ""
echo "==> Certificate generation complete!"
echo "Certificates are in: $CA_DIR"
echo ""
echo "Generated files:"
echo "  CA Certificate:      cacert.crt"
echo "  CA Private Key:      cakey.pem"
echo "  Server Certificate:  server-cert.crt"
echo "  Server Private Key:  server-private.pem"
echo "  Server Public Key:   server-public.pem"
echo "  Client Certificate:  client-cert.crt"
echo "  Client Private Key:  client-private.pem"
echo "  Client Public Key:   client-public.pem"
echo ""
echo "Your Registrar can now be accessed via:"
echo "  - IP address: 127.0.0.1"
echo "  - Hostname: localhost"
echo "  - Hostname: server"
