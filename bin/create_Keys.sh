##UNCOMMENT AND FILL THE VARIABLES
#PROJECT_NAME=dev-freelancer
#IBM_CLOUD_APIKEY=XXXXXXXXXX API KEY TO CONNECT TO IBM CLOUD ACCOUNT
#IBM_CLOUD_REGION=us-east
mkdir -p user_keys; cd user_keys
ibmcloud plugin install key-protect -r "IBM Cloud"
ibmcloud login --apikey ${IBM_CLOUD_APIKEY} -r ${IBM_CLOUD_REGION}
ibmcloud target -r ${IBM_CLOUD_REGION}


SERVICE_CREATED=$(ibmcloud resource service-instances | grep ${PROJECT_NAME}-srv || true)
if [ -z "${SERVICE_CREATED}" ]; then 
  ibmcloud resource service-instance-create ${PROJECT_NAME}-srv kms tiered-pricing ${IBM_CLOUD_REGION}
else 
  echo "****Service Already Created"
fi
SERVICE_INSTANCE=$(ibmcloud resource service-instance ${PROJECT_NAME}-srv --id | grep "::" | awk {'print $2'})
echo "****List Keys created "
ibmcloud kp keys --instance-id ${SERVICE_INSTANCE}
PRIVATE_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-private" | awk {'print $1'} || true )
PUBLIC_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-public" | awk {'print $1'} || true )

#CREATION OF THE SIGN KEY
cat >signsample <<EOF
      %echo Generating a basic OpenPGP key
      %no-protection
      Key-Type: DSA
      Key-Length: 1024
      Subkey-Type: ELG-E
      Subkey-Length: 1024
      Name-Real: SignSample
      Name-Email: signsample@foo.bar
      Expire-Date: 0
      Passphrase: abc
      %pubring signsample.pub
      %secring signsample.sec
      # Do a commit here, so that we can later print "done" :-)
      %commit
      %echo done
EOF
export GPG_TTY=$(tty)      
cat ~/.gnupg/gpg.conf
echo "*****Create gpg-agent.conf"
cat >/etc/gnupg/gpg-agent.conf <<EOF
      pinentry-program /usr/bin/pinentry-curses
      allow-loopback-pinentry
EOF
echo "*****Create gpg.conf"
cat >~/.gnupg/gpg.conf <<EOF
      use-agent 
      pinentry-mode loopback
EOF
gpg --batch -v --gen-key signsample
echo "*********Import the Public GPG to Keystore"
gpg --import signsample.pub
cat signsample.pub
echo "*********List Secret Keys"
gpg --list-secret-keys
echo "*********List Keys"
gpg --list-keys
echo "*********Make sigstore"
mkdir -p /source/sigstore/
chmod 777 /source/sigstore/
echo "*********Make sigstore "
echo "*********Change Path Sigstore"
sed -i "s/var\/lib\/containers\/sigstore/source\/sigstore/g" /etc/containers/registries.d/default.yaml
echo "*********Make sigstore"
cat /etc/containers/registries.d/default.yaml
ls -lsrt ~/.gnupg/
echo "*********Export public key"
gpg --armor --export signsample@foo.bar > ${PROJECT_NAME}Pub.pub
cat ${PROJECT_NAME}Pub.pub
echo "*********Export private key"
gpg --export-secret-key -a signsample@foo.bar > ${PROJECT_NAME}Priv.key
cat ${PROJECT_NAME}Priv.key

#WRAPPING THE KEY AND UPLOAD TO KEYPROTECTION.
if [ -z "${PRIVATE_KEY}" ] && [ -z "${PUBLIC_KEY}" ] ; then 
  echo "*****Keys are not created"
else 
  echo "****Keys Already Exists, Retriving the information"
  ibmcloud kp key delete --instance-id ${SERVICE_INSTANCE} ${PRIVATE_KEY}
  ibmcloud kp key delete --instance-id ${SERVICE_INSTANCE} ${PUBLIC_KEY}
fi
echo "****Create Key's on Key Protect"
ibmcloud kp key create kp-${PROJECT_NAME}-private -i ${SERVICE_INSTANCE}
ibmcloud kp key create kp-${PROJECT_NAME}-public -i ${SERVICE_INSTANCE}
echo "***** GET VALUES"
PRIVATE_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-private" | awk {'print $1'} || true)
PUBLIC_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-public" | awk {'print $1'} || true )
echo "***** WRAPPING"
ibmcloud kp key wrap ${PRIVATE_KEY} --instance-id ${SERVICE_INSTANCE} -p "$(cat ${PROJECT_NAME}Pub.pub | base64)" --output json | jq -r '.["Ciphertext"]' > PRIVATE_WRAP.pem
ibmcloud kp key wrap ${PUBLIC_KEY} --instance-id ${SERVICE_INSTANCE} -p "$(cat ${PROJECT_NAME}Priv.key | base64)" --output json | jq -r '.["Ciphertext"]' > PUBLIC_WRAP.pub
#THESE KEYS NEED TO BE SAVED IN ORDER TO UNNWRAP
echo "********Private Key wrap secret"
PRIVATE_WRAP=$(cat PRIVATE_WRAP.pem)
cat PRIVATE_WRAP.pem
echo "****Public Key wrap secret"
PUBLIC_WRAP=$(cat PUBLIC_WRAP.pub)
cat PUBLIC_WRAP.pub


#######THIS IS THE BLOCK TO UNWRAP
SERVICE_CREATED=$(ibmcloud resource service-instances | grep ${PROJECT_NAME}-srv || true)
SERVICE_INSTANCE=$(ibmcloud resource service-instance ${PROJECT_NAME}-srv --id | grep "::" | awk {'print $2'})
echo "****List Keys created "
ibmcloud kp keys --instance-id ${SERVICE_INSTANCE}
PRIVATE_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-private" | awk {'print $1'} || true )
PUBLIC_KEY=$(ibmcloud kp keys --instance-id ${SERVICE_INSTANCE} | grep "kp-${PROJECT_NAME}-public" | awk {'print $1'} || true )
ibmcloud kp keys --instance-id ${SERVICE_INSTANCE}
ibmcloud kp key unwrap ${PRIVATE_KEY} --instance-id ${SERVICE_INSTANCE} ${PRIVATE_WRAP} --output json | jq -r '.["Plaintext"]' > PRIVATE_B64.b64      
ibmcloud kp key unwrap ${PUBLIC_KEY} --instance-id ${SERVICE_INSTANCE} ${PUBLIC_WRAP} --output json | jq -r '.["Plaintext"]' > PUBLIC_B64.b64
echo "*********Export private key"
cat PRIVATE_B64.b64 | base64 --decode > Private_toImport.priv
cat PRIVATE_B64.b64 | base64 --decode
echo "*********Export public key"
cat PUBLIC_B64.b64 | base64 --decode > Public_toImport.pub
cat PUBLIC_B64.b64 | base64 --decode