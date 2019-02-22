for instance in controller0 controller1 controller2; do
  externalip="${instance}pub"
  scp encryption-config.yaml ubuntu@${!externalip}:~/
done