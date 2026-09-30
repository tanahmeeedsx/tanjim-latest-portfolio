# DevOps Portfolio — Nginx on AWS EC2 with GitHub Actions

This repository deploys the portfolio as a **static website served directly by Nginx** on an Ubuntu EC2 instance.

There is no Node.js application process in production. For this portfolio, that is intentional: the site consists of static HTML and a PDF resume, so Nginx is the simpler and more efficient runtime.

## Architecture

```text
Developer
   |
   | git push main
   v
GitHub
   |
   v
GitHub Actions
   |-- validate index.html + resume.pdf
   |-- validate local HTML references
   |-- package immutable release.tar.gz
   |-- authenticate to AWS with IAM access keys
   |-- discover EC2 by EC2_HOST
   |-- generate temporary SSH key
   |-- EC2 Instance Connect
   |-- upload release
   v
AWS EC2 (Ubuntu)
   |
   | /var/www/devops-portfolio/releases/<git-sha>
   | /var/www/devops-portfolio/current -> active release
   v
Nginx :80 / :443
   |
   v
Browser
```

A failed deployment automatically moves the `current` symlink back to the previous release and reloads Nginx.

---

## Repository layout

```text
.
├── .github/
│   └── workflows/
│       └── deploy.yml
├── infra/
│   ├── iam/
│   │   └── github-actions-ec2-instance-connect-policy.json
│   └── nginx/
│       └── portfolio.conf
├── scripts/
│   ├── bootstrap-ec2.sh
│   └── validate-site.sh
├── site/
│   ├── index.html
│   └── resume.pdf
├── tests/
│   └── check-local-references.py
├── .gitignore
└── README.md
```

Your deployable website lives only under `site/`.

---


# 1. Prerequisites

You need:

- An AWS account
- A GitHub repository
- An Ubuntu EC2 instance
- An EC2 public IPv4 address (an Elastic IP is strongly recommended)
- An IAM user/access key for the GitHub Actions deployment
- Your original EC2 PEM key **only for the one-time bootstrap**

The GitHub workflow uses these repository secrets:

```text
EC2_HOST
EC2_USER
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
```

For Ubuntu:

```text
EC2_USER=ubuntu
```

You do **not** store your EC2 PEM/private key in GitHub. GitHub Actions uses EC2 Instance Connect to push a temporary SSH public key.

---

# 2. Create the EC2 instance

In AWS Console:

1. Open **EC2 → Instances → Launch instances**.
2. Name it, for example: `devops-portfolio`.
3. Select a current Ubuntu Server LTS AMI.
4. A small instance such as `t3.micro` is enough for a static portfolio.
5. Create/select a key pair. Keep the `.pem` file securely on your computer.
6. Assign storage; the default size is normally sufficient.
7. Launch the instance.

## Recommended Elastic IP

Because the GitHub Secret `EC2_HOST` contains the public IP, assign an **Elastic IP** so the address does not change when the instance is stopped/started.

---

# 3. Configure the EC2 Security Group

Required inbound rules:

| Type | Port | Source | Purpose |
|---|---:|---|---|
| HTTP | 80 | `0.0.0.0/0` and `::/0` | Public website |
| HTTPS | 443 | `0.0.0.0/0` and `::/0` | HTTPS after TLS setup |
| SSH | 22 | See note below | GitHub Actions deployment |

### Important SSH networking note

EC2 Instance Connect makes the SSH **credential temporary**, but the GitHub-hosted runner still needs network access to TCP/22 on the EC2 instance.

For a classroom/demo deployment, the simplest setup is to allow port 22 broadly while relying on SSH keys and EC2 Instance Connect. This increases exposure and is not my preferred long-term production design.

For a stronger production design, use one of these instead:

- a self-hosted GitHub Actions runner inside your VPC,
- AWS Systems Manager Session Manager/Run Command,
- an EC2 Instance Connect Endpoint/private network path,
- or dynamically restrict the Security Group to the runner address.

Keep port 22 closed from unnecessary sources whenever possible.

---

# 4. Bootstrap EC2 once

This installs Nginx, EC2 Instance Connect, creates the release directories, and installs the Nginx site configuration.

From your local machine, unzip this repository and run:

```bash
chmod 400 ~/Downloads/YOUR-KEY.pem

scp -i ~/Downloads/YOUR-KEY.pem \
  scripts/bootstrap-ec2.sh \
  ubuntu@YOUR_EC2_IP:/tmp/bootstrap-ec2.sh
```

SSH to EC2:

```bash
ssh -i ~/Downloads/YOUR-KEY.pem ubuntu@YOUR_EC2_IP
```

Run bootstrap:

```bash
sudo bash /tmp/bootstrap-ec2.sh
```

Check Nginx:

```bash
sudo systemctl status nginx --no-pager
sudo nginx -t
```

At this point Nginx is running, but the portfolio is not active until the first GitHub Actions deployment creates:

```text
/var/www/devops-portfolio/current
```

---

# 5. Create the IAM deployment user

Create a dedicated IAM user for GitHub Actions rather than using administrator/root credentials.

Example name:

```text
github-actions-portfolio
```

Create an access key for this user and save:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

Do not commit these values to Git.

---

# 6. Find your AWS EC2 instance ID


Instance ID can be found in **EC2 → Instances** or with:

```bash
aws ec2 describe-instances \
  --filters "Name=ip-address,Values=YOUR_EC2_IP" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text
```

---

# 7. Configure the IAM policy

A least-privilege starter policy is included at:

```text
infra/iam/github-actions-ec2-instance-connect-policy.json
```

Edit these placeholders:

```text
YOUR_REGION
YOUR_AWS_ACCOUNT_ID
YOUR_INSTANCE_ID
```

Example resource:

```text
arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0
```

The policy allows:

```text
ec2:DescribeInstances
ec2-instance-connect:SendSSHPublicKey
```

The Instance Connect permission is restricted to the selected instance and to the Linux user `ubuntu`.

Attach the policy to the IAM user you created for GitHub Actions.

---

# 8. Add GitHub repository secrets

Open your GitHub repository:

**Settings → Secrets and variables → Actions → New repository secret**

Create exactly these secrets.

## `EC2_HOST`

Your EC2 public/Elastic IP:

```text
54.123.45.67
```

Do not include `http://`.

## `EC2_USER`

For an Ubuntu AMI:

```text
ubuntu
```

## `AWS_ACCESS_KEY_ID`

Your dedicated IAM user's access key ID.

## `AWS_SECRET_ACCESS_KEY`

The matching IAM secret access key.

## `AWS_REGION`

For example:

```text
us-east-1
```

The region must match the EC2 instance.

---

# 9. Push the repository to GitHub

Create an empty GitHub repository, then from this project directory:

```bash
git init
git add .
git commit -m "Initial Nginx portfolio deployment"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPOSITORY.git
git push -u origin main
```

The push to `main` starts the workflow automatically.

---

# 10. What GitHub Actions does

Workflow:

```text
.github/workflows/deploy.yml
```

## CI/validation job

Before anything is deployed, Actions:

1. Checks out the repository.
2. Confirms `site/index.html` exists.
3. Confirms `site/resume.pdf` exists.
4. Performs basic HTML structure checks.
5. Checks local `href`/`src` references for missing files.
6. Packages only `site/` into `release.tar.gz`.
7. Stores that exact validated archive as the build artifact.

If validation fails, **deployment never starts**.

## Deployment job

After validation succeeds:

1. Downloads the exact validated artifact.
2. Authenticates to AWS with:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
```

3. Looks up the running EC2 instance using `EC2_HOST`.
4. Reads its Instance ID and Availability Zone.
5. Generates a temporary Ed25519 SSH key on the GitHub runner.
6. Sends its public key through EC2 Instance Connect.
7. Uploads `release.tar.gz` to the EC2 instance.
8. Creates a release directory named after the Git commit SHA.
9. Extracts the website there.
10. Changes the `current` symlink to that release.
11. Runs `nginx -t`.
12. Reloads Nginx.
13. Calls `/health` and `/` locally on EC2.
14. Calls `/health` and `/` through the public EC2 IP.
15. Keeps the five newest releases.

---

# 11. Release structure on EC2

After several deployments:

```text
/var/www/devops-portfolio/
├── current -> /var/www/devops-portfolio/releases/8d2e5...
└── releases/
    ├── 8d2e5...
    ├── 72fca...
    └── 164b3...
```

Nginx always serves:

```text
/var/www/devops-portfolio/current
```

The site is not copied directly over the active files. A complete new release is prepared first, then the symlink switches to it.

---

# 12. Automatic rollback

Suppose the currently active release is:

```text
current -> releases/OLD_SHA
```

A new deployment creates:

```text
releases/NEW_SHA
```

Actions then switches:

```text
current -> releases/NEW_SHA
```

It validates Nginx and performs HTTP health checks.

If activation fails, the deployment script restores:

```text
current -> releases/OLD_SHA
```

and reloads Nginx.

The failed release is removed.

---

# 13. Manual rollback

SSH to EC2 and inspect releases:

```bash
ls -lt /var/www/devops-portfolio/releases
readlink -f /var/www/devops-portfolio/current
```

Select a previous release:

```bash
PREVIOUS_SHA=YOUR_PREVIOUS_GIT_SHA
```

Switch the symlink:

```bash
sudo ln -sfn \
  /var/www/devops-portfolio/releases/$PREVIOUS_SHA \
  /var/www/devops-portfolio/current
```

Validate and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Check:

```bash
curl -i http://127.0.0.1/health
curl -I http://127.0.0.1/
```

---

# 14. Health check

Nginx exposes:

```text
GET /health
```

Expected response:

```text
ok
```

Local EC2 test:

```bash
curl http://127.0.0.1/health
```

Public test:

```bash
curl http://YOUR_EC2_IP/health
```

---

# 15. View the site

Open:

```text
http://YOUR_EC2_IP
```

The Resume buttons point to `resume.pdf` and the portfolio HTML is already configured to open the resume in a new browser tab.

---

# 16. Nginx operations

Check configuration:

```bash
sudo nginx -t
```

Reload without stopping the web server:

```bash
sudo systemctl reload nginx
```

Restart:

```bash
sudo systemctl restart nginx
```

Status:

```bash
sudo systemctl status nginx --no-pager
```

Access log:

```bash
sudo tail -f /var/log/nginx/access.log
```

Error log:

```bash
sudo tail -f /var/log/nginx/error.log
```

---

# 17. Update the portfolio

Edit files inside:

```text
site/
```

For example:

```text
site/index.html
site/resume.pdf
```

Then:

```bash
git add .
git commit -m "Update portfolio"
git push origin main
```

GitHub Actions validates and deploys the new release automatically.

---

# 18. Test validation locally

Before pushing:

```bash
./scripts/validate-site.sh site
python3 tests/check-local-references.py site
```

Expected output resembles:

```text
Site validation passed.
Local reference validation passed (... href/src references checked).
```

---

# 19. Add a domain

Create an A record with your DNS provider:

```text
portfolio.example.com -> YOUR_ELASTIC_IP
```

Then edit the Nginx configuration on EC2:

```bash
sudo nano /etc/nginx/sites-available/devops-portfolio
```

Change:

```nginx
server_name _;
```

to:

```nginx
server_name portfolio.example.com;
```

Validate and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

# 20. Enable HTTPS with Let's Encrypt

After the domain resolves to the EC2 Elastic IP:

```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
```

Issue the certificate:

```bash
sudo certbot --nginx -d portfolio.example.com
```

Test renewal:

```bash
sudo certbot renew --dry-run
```

Ensure inbound TCP/443 is open in the Security Group.

After HTTPS is enabled, use:

```text
https://portfolio.example.com
```

---

# 21. Troubleshooting

## Workflow cannot find the instance

Confirm:

- `EC2_HOST` contains only the current public/Elastic IP.
- `AWS_REGION` is correct.
- The instance is running.
- IAM has `ec2:DescribeInstances`.

Run locally if your AWS CLI is configured:

```bash
aws ec2 describe-instances \
  --filters \
    "Name=ip-address,Values=YOUR_EC2_IP" \
    "Name=instance-state-name,Values=running"
```


## SSH times out

This is usually networking, not IAM.

Check:

- EC2 has a public IP,
- Security Group permits TCP/22 from the runner/network path,
- subnet route table has an Internet Gateway route,
- network ACLs permit the traffic,
- `sshd` is running.

On EC2:

```bash
sudo systemctl status ssh --no-pager
```

## Website returns 404 after bootstrap

That is expected before the first successful deployment because `current` has not yet been created.

Inspect:

```bash
ls -lah /var/www/devops-portfolio
```

After deployment you should see the `current` symlink.

## Nginx configuration fails

```bash
sudo nginx -t
sudo journalctl -u nginx -n 100 --no-pager
```

## Resume does not open

Check:

```bash
ls -lh /var/www/devops-portfolio/current/resume.pdf
curl -I http://127.0.0.1/resume.pdf
```

---

# 22. Security improvements for a real production environment

This project intentionally matches the requested GitHub Secret model using long-lived IAM access keys.

For a stronger setup, the next improvements would be:

1. Replace `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` with **GitHub OIDC + an IAM role**.
2. Remove broad public SSH access by using SSM, a private runner, or an EC2 Instance Connect Endpoint.
3. Restrict the IAM policy to the exact EC2 instance.
4. Protect the GitHub `production` environment with approval rules.
5. Enable HTTPS only and redirect HTTP to HTTPS.
6. Add CloudWatch/uptime monitoring.
7. Use a custom domain and an Elastic IP.

The current design already avoids storing the EC2 PEM private key in GitHub.

---

# 23. Cost considerations

For this static portfolio, the main AWS costs are typically:

- EC2 instance runtime,
- EBS volume,
- public IPv4/Elastic IPv4 charges where applicable,
- outbound data transfer,
- optional domain registration.

Nginx serves the site directly, so there is no application runtime, database, container platform, or managed load balancer required.

For a higher-traffic static portfolio, an object-storage/CDN design such as S3 + CloudFront would normally be more scalable and can be more cost-efficient. This EC2 design is intentionally useful as a DevOps/CI/CD demonstration.

---

# 24. Cleanup strategy

To avoid ongoing AWS charges when the project is no longer needed:

1. Remove DNS records pointing to the instance.
2. Terminate the EC2 instance.
3. Delete the EBS volume if it was not configured for deletion with the instance.
4. Release the Elastic IP when no longer needed.
5. Delete the dedicated IAM user's access keys.
6. Delete the IAM user/policy if it is no longer used.
7. Remove the GitHub repository secrets.

Before terminating anything, back up files you want to keep.

---

# Deployment summary

```text
Code change
   |
git push main
   |
GitHub Actions
   |
Validate site
   |
Build release.tar.gz
   |
AWS IAM authentication
   |
EC2 Instance Connect
   |
Upload immutable release
   |
/var/www/devops-portfolio/releases/<SHA>
   |
current symlink switch
   |
nginx -t
   |
Nginx reload
   |
/health + homepage checks
   |
SUCCESS
```

If activation fails:

```text
FAILED NEW RELEASE
        |
        v
current -> previous release
        |
        v
nginx reload
        |
        v
ROLLBACK COMPLETE
```

This gives the portfolio itself a concrete DevOps story: validation, immutable releases, least-privilege deployment access, Nginx, health checks, rollback, security considerations, cost awareness, and cleanup.
