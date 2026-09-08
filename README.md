# yeet-devops

Infrastructure for yeet.family. Hetzner Cloud **Ashburn (us-east)** for the backend, Cloudflare for everything user-facing.

```
Internet ──▶ Cloudflare (DNS, TLS, WAF, rate limits, bot mgmt, DDoS, cache, Pages, R2)
                 │ outbound-only tunnel (QUIC)
                 ▼
   ┌── Hetzner private net 10.10.1.0/24 ─────────────────────────────────────────┐
   │ monolith  10.10.1.10  CCX33   yeet-backend + app Postgres + cloudflared +    │
   │                               prometheus/grafana        (no inbound ports)  │
   │ timescale 10.10.1.20  CCX33   TimescaleDB              (no public IPv4)     │
   └─────────────────────────────────────────────────────────────────────────────┘
```

Only-Cloudflare guarantee, three layers deep:
1. **Hetzner Cloud firewall**: monolith has zero inbound rules (ICMP only); timescale has none and no public IPv4.
2. **nftables on the box**: default-drop input; timescale accepts 5432/9100/9187/22 from 10.10.1.10 only.
3. **cloudflared tunnel**: the backend listens on 127.0.0.1:8080; the only path in is the tunnel, so every request already passed Cloudflare's WAF, rate limiting, bot scoring and DDoS layers. SSH and Grafana are behind Zero Trust Access (email allow-list).

## Layout
```
terraform/   hcloud + cloudflare (tunnel, DNS, zone settings, WAF/rate-limit/cache rulesets, Access, R2, Pages)
  templates/ cloud-init for both servers (nftables, sysctl, docker, compose, env)
compose/     docker-compose + configs baked into cloud-init (monolith/, timescale/)
scripts/     bootstrap.sh (create), ssh.sh (tunnel ssh), deploy.sh (roll image), switch-chain.sh (mainnet flip), scale-tunnel.sh
```

## First run
1. Cloudflare: zone `yeet.family` on Cloudflare; create an API token (Zone: DNS, Zone Settings, Zone WAF, Cache Rules; Account: Cloudflare Tunnel, Access: Apps & Policies, R2, Pages). Create R2 bucket `yeet-tfstate` + an R2 API token for terraform state → `terraform/backend.hcl`.
2. Hetzner: project + API token (`hcloud context create yeet`).
3. `cp terraform/terraform.tfvars.example terraform/terraform.tfvars`, fill; export the `TF_VAR_*` secrets.
4. `scripts/bootstrap.sh` → creates network, both servers, firewalls, tunnel, DNS, rules, R2, Pages. ~3 minutes; cloud-init needs another ~3.
5. `scripts/ssh.sh monolith 'cloud-init status --wait && docker compose -f /opt/yeet/docker-compose.yml ps'`.
6. Create an R2 API token for image uploads, put it in `/opt/yeet/backend.env` (`R2_ACCESS_KEY_ID/SECRET`), `docker compose up -d backend`.
7. `curl https://api.yeet.family/healthz`.

## Day 2
- New backend: `scripts/deploy.sh <tag>` (image from yeet-backend's GitHub Actions → ghcr).
- Mainnet: `scripts/switch-chain.sh arc-mainnet <tag>` then `terraform apply` with `yeet_chain = "arc-mainnet"`.
- More WS capacity: `scripts/scale-tunnel.sh 3`.
- Timescale shell: `scripts/ssh.sh timescale 'docker exec -it timescale psql -U postgres -d yeet_ts'`.

## Notes
- Cloudflare plan limits: Free = 1 rate-limit rule; Pro = 2; Business = 5. `cloudflare_edge.tf` defines 3 → on Free keep only `rl_api`, or upgrade to Pro ($20/mo, also unlocks `enable_managed_waf` and bot score).
- `/api/v1/tokens/launch` bot protection = Cloudflare **Turnstile** (frontend widget + backend verification), not a WAF challenge: challenges cannot be solved by `fetch()`. Rate limit 5/min/IP is the backstop.
- Cloud-init runs once; `hcloud_server.user_data` changes are ignored on purpose. Config drift after day 1 goes through `scripts/`.
- Destroying the timescale server destroys the data (local NVMe). Everything in it is re-derivable by replaying the indexer from the deploy block.
