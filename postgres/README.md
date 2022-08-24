# POSTGRES HELM CHART
This is a simple postgres helm chart.

## INSTALL

from this directory run the following command to install an instance of postgres:
```bash
helm install <name> .
```

The `name` of the installation is important as it will then corespond to the deployment and service name of the postgres instance you are creating. So if you install like this:

```bash
helm install my-postgres .
```

You will get an instance of postgres in the present namespace called `my-postgres`

### CONNECTING TO POSTGRES 
Before you can connect you need to port-forward the deployment like this:

```bash
kubectl port-forward service/postgres 5432:5432
```

Assuming you have `psql` installed on your desktop you need to run:

```bash
psql -h localhost -p 5432 -U postgres
```

And you should connect.

### DEFAULT PASSWORD 
The default password is `password`

If you want to create with a different password you need to pass the following when you install the helm chart:

```bash
helm install my-postgres --set password=<some-password>
```

### DELETING INSTANCE PVCs 
If you create an postgres instance then delete it, it's PVC (Persistent Volume Claim) will NOT be deleted.  If you then recreate your postgres instance it will reclaim the old PVC which may not be the behavior you want (this may also involve mounting postgres with the OLD password)

to delete postgres via helm:

```bash
helm delete <name>
```

And you must then delete the PVC via:

```bash
kubectl delete pvc <name>
```

Where `name` is the helm install name.
