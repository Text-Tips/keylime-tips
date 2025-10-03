#!/bin/bash
# Script to generate Registrar TLS certificates for Push Model Agent communication
# This generates the same structure that Keylime uses when tls_dir="generate" for registrar

set -e

WORK_DIR="${KEYLIME_WORK_DIR:-/var/lib/keylime}"
REG_CA_DIR="${WORK_DIR}/reg_ca"

echo "=== Keylime Registrar TLS Certificate Generator ==="
echo ""
echo "This script generates TLS certificates for the Registrar to support"
echo "TLS communication with Push Model Agents."
echo ""
echo "Generated files will be placed in: ${REG_CA_DIR}"
echo ""

# Check if directory exists
if [ -d "${REG_CA_DIR}" ]; then
    if [ -f "${REG_CA_DIR}/cacert.crt" ]; then
        echo "Warning: CA certificate already exists at ${REG_CA_DIR}/cacert.crt"
        read -p "Do you want to regenerate (this will overwrite existing certs)? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Exiting without changes."
            exit 0
        fi
    fi
fi

# Create directory with proper permissions
echo "Creating directory: ${REG_CA_DIR}"
mkdir -p "${REG_CA_DIR}"
chmod 700 "${REG_CA_DIR}"

cd "${REG_CA_DIR}"

echo ""
echo "Step 1: Generating CA private key and certificate..."
echo "----------------------------------------"

# Generate CA private key (RSA 3072-bit for strong security)
openssl genrsa -out ca-private.pem 3072 2>/dev/null
chmod 600 ca-private.pem
echo "✓ CA private key generated: ca-private.pem"

# Generate CA certificate (valid for 10 years)
openssl req -new -x509 -days 3650 \
    -key ca-private.pem \
    -out cacert.crt \
    -subj "/CN=Keylime Registrar CA/O=Keylime/OU=Registrar" \
    2>/dev/null
chmod 644 cacert.crt
echo "✓ CA certificate generated: cacert.crt"

echo ""
echo "Step 2: Generating server private key and certificate..."
echo "----------------------------------------"

# Generate server private key
openssl genrsa -out server-private.pem 3072 2>/dev/null
chmod 600 server-private.pem
echo "✓ Server private key generated: server-private.pem"

# Create server certificate signing request
openssl req -new \
    -key server-private.pem \
    -out server.csr \
    -subj "/CN=Keylime Registrar Server/O=Keylime/OU=Registrar" \
    2>/dev/null
echo "✓ Server CSR generated: server.csr"

# Create extension file for SAN (Subject Alternative Names)
cat > server-ext.cnf << 'EOF'
[v3_req]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
IP.1 = 127.0.0.1
DNS.1 = localhost
DNS.2 = registrar
EOF

echo "✓ Server extension config created"

# Sign server certificate with CA (valid for 5 years)
openssl x509 -req -days 1825 \
    -in server.csr \
    -CA cacert.crt \
    -CAkey ca-private.pem \
    -CAcreateserial \
    -out server-cert.crt \
    -extensions v3_req \
    -extfile server-ext.cnf \
    2>/dev/null
chmod 644 server-cert.crt
echo "✓ Server certificate generated: server-cert.crt"

# Clean up CSR and extension file
rm -f server.csr server-ext.cnf ca-private.pem.srl

echo ""
echo "Step 3: Verifying certificate chain..."
echo "----------------------------------------"

# Verify the server certificate
if openssl verify -CAfile cacert.crt server-cert.crt 2>&1 | grep -q "OK"; then
    echo "✓ Server certificate verification: PASSED"
else
    echo "✗ Server certificate verification: FAILED"
    exit 1
fi

# Display SAN information
echo ""
echo "Subject Alternative Names in server certificate:"
openssl x509 -in server-cert.crt -noout -text | grep -A1 "Subject Alternative Name" || echo "  WARNING: No SAN found!"

echo ""
echo "Certificate subject:"
openssl x509 -in server-cert.crt -noout -subject

echo ""
echo "=== Certificate Generation Complete ==="
echo ""
echo "Generated files in ${REG_CA_DIR}:"
echo "  - cacert.crt          (CA certificate - distribute to agents)"
echo "  - ca-private.pem      (CA private key - keep secure!)"
echo "  - server-cert.crt     (Server certificate)"
echo "  - server-private.pem  (Server private key - keep secure!)"
echo ""
echo "File permissions:"
ls -lh "${REG_CA_DIR}"
echo ""
echo "=== Registrar Configuration ==="
echo ""
echo "Add/verify these settings in your Registrar configuration:"
echo ""
echo "[registrar]"
echo "tls_dir = generate                    # or: ${REG_CA_DIR}"
echo "server_cert = default                 # Uses: server-cert.crt"
echo "server_key = default                  # Uses: server-private.pem"
echo "trusted_client_ca = default           # Uses: cacert.crt"
echo "server_key_password =                 # Empty (no password)"
echo ""
echo "=== Agent Configuration (for TLS) ==="
echo ""
echo "[agent]"
echo "registrar_ip = <registrar_host>"
echo "registrar_port = 8891                            # Use tls_port, not regular port"
echo "registrar_tls_enabled = true"
echo "registrar_tls_ca_cert = ${REG_CA_DIR}/cacert.crt"
echo "registrar_tls_client_cert = <path_to_agent_cert>  # Generate with keylime_ca"
echo "registrar_tls_client_key = <path_to_agent_key>    # Generate with keylime_ca"
echo ""
echo "To generate client certificates for agents, use:"
echo "  keylime_ca -d ${REG_CA_DIR} --command mkcert --name <agent_name>"
echo ""
echo "Done!"

