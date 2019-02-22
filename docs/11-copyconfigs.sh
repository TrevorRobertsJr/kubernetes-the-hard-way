for instance in worker0 worker1 worker2; do
  externalip="${instance}pub"
  scp ${instance}.kubeconfig kube-proxy.kubeconfig ubuntu@${!externalip}:~/
done

for instance in controller0 controller1 controller2; do
  externalip="${instance}pub"
  scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ubuntu@${!externalip}:~/
done