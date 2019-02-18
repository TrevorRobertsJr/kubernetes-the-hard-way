for instance in worker0 worker1 worker2; do

# Get external and internal IP addresses from environment variables
externalip="${instance}pub"
internalip="${instance}prv"

cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${!instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Brooklyn",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "New York"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${!instance},${externalip},${internalip} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}
done