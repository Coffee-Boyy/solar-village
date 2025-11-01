# Solar Village

**Local Multipass / Ansible Test Environment**

This README walks you through setting up a **four-node local cluster** that mirrors the production-grade decentralized infrastructure:

* **3× MySQL 8.4 Group Replication** (multi-primary)
* **1× Async replica node**
* **4× Garage distributed object storage nodes**
* **4× Ushahidi containers + Traefik reverse proxies**
* **WireGuard mesh** connecting all VMs over a private overlay network

The entire environment runs on your laptop via **Multipass** and is orchestrated with **Ansible**.
It provides a realistic multi-cloud testbed — minus the cloud billing.

---

## 🧰 Requirements

| Tool          | Version | Notes                                       | Install Link |
| ------------- | ------- | ------------------------------------------- | ---- |
| **Multipass** | ≥ 1.13  | Launch lightweight Ubuntu 24.04 VMs         | https://canonical.com/multipass/install |
| **Ansible**   | ≥ 2.16  | Manages install, WireGuard, Docker, Traefik | `pip install ansible` |
| **Docker**    | –       | Installed inside each VM by Ansible         | - |
| **SSH key**   | –       | `~/.ssh/id_ed25519.pub` used for access     | - |

> 🐧 Works on Linux, macOS, and Windows 11 (via WSL + Multipass).

---

## Step 0 - Install Dependencies

Create a new Python virtual environment to install the Ansible CLI:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install ansible-core
ansible --version
```

---

## 🏗️ Step 1 — Launch VMs

Create four Ubuntu 24.04 VMs (2 CPU / 4 GB RAM / 30 GB disk):

```bash
multipass launch 24.04 --name do-a --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name do-b --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name hz-a --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name hz-b --cpus 2 --memory 4G --disk 30G

multipass list
```

Note each VM’s IP address.

---

## 🔑 Step 2 — Authorize SSH Access

Create a personal SSH key (if you don't already have one):
```bash
ssh-keygen -t ed25519
```

Inject your local SSH public key into each VM:

```bash
for h in do-a do-b hz-a hz-b; do
  multipass exec $h -- bash -c "mkdir -p /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && echo '$(cat ~/.ssh/id_ed25519.pub)' >> /home/ubuntu/.ssh/authorized_keys && chmod 600 /home/ubuntu/.ssh/authorized_keys"
done
```

---

## 🗺️ Step 3 — Create Ansible Inventory

`ansible/inventories/local/hosts.ini`

```ini
[all]
do-a ansible_host=<IP_DO_A> ansible_user=ubuntu wg_ip=10.20.0.11 wg_port=51821 node_role=gr_primary
do-b ansible_host=<IP_DO_B> ansible_user=ubuntu wg_ip=10.20.0.12 wg_port=51822 node_role=gr_primary
hz-a ansible_host=<IP_HZ_A> ansible_user=ubuntu wg_ip=10.20.0.13 wg_port=51823 node_role=gr_primary
hz-b ansible_host=<IP_HZ_B> ansible_user=ubuntu wg_ip=10.20.0.14 wg_port=51824 node_role=async_replica

[wg_all]
do-a
do-b
hz-a
hz-b

[mysql_gr]
do-a
do-b
hz-a

[mysql_async]
hz-b

[garage_all]
do-a
do-b
hz-a
hz-b

[ushahidi_all]
do-a
do-b
hz-a
hz-b
```

Replace each `<IP_…>` with the actual Multipass IPs.

---

## 🧩 Step 4 — Run the Playbook

Install dependencies and deploy:

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
ansible-playbook ansible/site.yml
```

Ansible will:

1. Install WireGuard on each VM.
2. Generate keys locally (per host) and mesh them.
3. Enable Docker and UFW rules.
4. Deploy Traefik (reverse proxy + TLS).
5. Bring up MySQL Group Replication + Router.
6. Deploy Garage (distributed S3-compatible storage).
7. Launch Ushahidi containers on each node.

---

## ✅ Step 5 — Verify Deployment

### WireGuard mesh

```bash
ansible -i ansible/inventories/local/hosts.ini all -m command -a "sudo wg show"
```

Each node should list 3 peers with `latest handshake` < 30 s.

### MySQL Group Replication

```bash
ssh ubuntu@<IP_DO_A> "docker exec mysql mysql -uroot -p'rootpass' -e \"SELECT MEMBER_HOST,MEMBER_STATE FROM performance_schema.replication_group_members;\""
```

Expect 3 members ONLINE.

### Garage cluster

Garage will be accessible at `http://<IP_DO_A>:3900` (S3 API) and `http://<IP_DO_A>:3903` (Admin API).

After initial deployment, you'll need to:
1. Initialize the cluster (on first node): `docker exec garage garage layout apply --version 1`
2. Add nodes to the cluster layout
3. Create the bucket: `docker exec garage garage bucket create ushahidi-uploads`
4. Create access keys: `docker exec garage garage key new --name ushahidi-key`
5. Configure bucket permissions

For detailed Garage setup instructions, see: https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/

### Ushahidi UI

Visit `http://<IP_DO_A>:8080` (or any node's :8080).
Sign up, create a test post, upload a file, confirm it appears in Garage.

---

## 🧪 Step 6 — Functional Tests

| Test               | Command                    | Expected                 |
| ------------------ | -------------------------- | ------------------------ |
| Ping peers over WG | `ping -c2 10.20.0.12`      | Replies                  |
| Add post on Node A | via Ushahidi UI            | Appears on Node B        |
| Check GR quorum    | SQL query above            | All ONLINE               |
| Restart Node B     | `multipass restart do-b`   | GR rejoins automatically |
| Upload file        | Ushahidi UI → Garage bucket | File visible             |

---

## 🧹 Cleanup

Stop containers and delete VMs:

```bash
ansible -i ansible/inventories/local/hosts.ini all -m command -a "docker ps -q | xargs -r docker stop"
multipass delete --purge do-a do-b hz-a hz-b
```

---

## 🧠 How This Maps to Production

| Component       | Local (Multipass)   | Cloud Equivalent                        |
| --------------- | ------------------- | --------------------------------------- |
| VM nodes        | Multipass VMs       | DigitalOcean Droplets / Hetzner Servers |
| Private network | WireGuard mesh      | Inter-cloud overlay                     |
| DB cluster      | MySQL GR containers | Same (multi-region GR)                  |
| Object store    | Garage containers    | Garage pods or S3-compatible buckets     |
| Reverse proxy   | Traefik containers  | Per-node Traefik + ACME DNS-01          |
| Deployment      | Ansible playbook    | GitHub Actions / Terraform + Ansible    |

---

## ⚠️ Common Issues & Fixes

| Symptom                      | Likely Cause                  | Fix                                                      |
| ---------------------------- | ----------------------------- | -------------------------------------------------------- |
| `wg show` shows no handshake | UDP port blocked              | `sudo ufw allow 5182x/udp` on each VM                    |
| `GROUP_REPLICATION` OFFLINE  | Seed IP typo or network delay | Re-run playbook or start GR manually                     |
| Garage not accessible        | Container restart timing      | `docker compose restart garage`                           |
| Ushahidi 500 error           | DB not ready yet              | Wait 30 s and refresh                                    |
| DNS name not resolving       | Local host mapping needed     | `sudo nano /etc/hosts` → `<IP_DO_A> ushahidi.local.test` |

---

## 🧭 Next Steps

* Add **CI/CD**: run Terraform → Ansible on cloud nodes.
* Integrate **GitHub Actions** for idempotent deploys.
* Extend **WireGuard** to additional community nodes.
* Add **Prometheus + Grafana** dashboards for GR / Garage health.
* Run **chaos tests**: kill nodes, verify auto-recovery.

---

**Congratulations! 🎉**
You now have a fully working, decentralized Ushahidi + MySQL Group Replication + Garage stack running on your laptop — complete with private WireGuard networking and per-node Ushahidi instances.
