# Generate the default CA method.
```
$ cfssl gencert -initca default-ca-csr.json | cfssljson -bare ca
```
