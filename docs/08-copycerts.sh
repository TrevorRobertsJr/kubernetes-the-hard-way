for instance in worker0 worker1 worker2; do
  externalip="${instance}pub"
  scp ca.pem ${instance}-key.pem ${instance}.pem ubuntu@${!externalip}:~/
done

for instance in controller0 controller1 controller2; do
  externalip="${instance}pub"
  scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem ubuntu@${!externalip}:~/
done