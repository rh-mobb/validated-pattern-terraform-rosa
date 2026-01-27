#!/usr/bin/env python3
"""
Verify Cluster Deployment Script

Verifies that:
1. Cluster is deployed and accessible
2. GitOps operator is deployed
3. ApplicationSet from cluster-config is deployed (default: cluster-config-applicationset)

Usage:
    python3 scripts/verify_cluster.py <cluster-name>
    # or
    ./scripts/verify_cluster.py <cluster-name>

Requirements:
    - Python 3.7+
    - kubernetes>=28.0.0
    - boto3 (for AWS Secrets Manager)
    - terraform (in PATH)
    - AWS CLI configured (for Secrets Manager access)
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Optional, Tuple

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
except ImportError:
    print("ERROR: kubernetes library not found. Install with: pip install kubernetes")
    sys.exit(1)

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("ERROR: boto3 library not found. Install with: pip install boto3")
    sys.exit(1)


# Colors for output
class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color


def print_info(msg: str):
    print(f"{Colors.BLUE}ℹ {msg}{Colors.NC}")


def print_success(msg: str):
    print(f"{Colors.GREEN}✓ {msg}{Colors.NC}")


def print_warning(msg: str):
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.NC}")


def print_error(msg: str):
    print(f"{Colors.RED}✗ {msg}{Colors.NC}")


def get_project_root() -> Path:
    """Get the project root directory."""
    script_dir = Path(__file__).parent
    return script_dir.parent


def get_terraform_dir() -> Path:
    """Get the Terraform infrastructure directory."""
    project_root = get_project_root()
    return project_root / "terraform"


def run_terraform_output(output_name: str, terraform_dir: Path) -> Optional[str]:
    """Run terraform output and return the value."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True,
            timeout=30
        )
        value = result.stdout.strip()
        return value if value and value != "null" else None
    except subprocess.CalledProcessError as e:
        print_warning(f"Failed to get terraform output '{output_name}': {e.stderr}")
        return None
    except subprocess.TimeoutExpired:
        print_error(f"terraform output '{output_name}' timed out")
        return None


def get_admin_password(terraform_dir: Path) -> Optional[str]:
    """Get admin password from AWS Secrets Manager or environment variable."""
    # Check environment variable first
    admin_password = os.environ.get("TF_VAR_admin_password_override") or os.environ.get("ADMIN_PASSWORD")
    if admin_password:
        print_info("Using admin password from environment variable")
        return admin_password

    # Get secret ARN from Terraform output
    secret_arn = run_terraform_output("admin_password_secret_arn", terraform_dir)
    if not secret_arn:
        print_error("admin_password_secret_arn not found in Terraform outputs")
        return None

    if not secret_arn.startswith("arn:aws:secretsmanager:"):
        print_error(f"Invalid secret ARN format: {secret_arn}")
        return None

    # Extract region from ARN
    # Format: arn:aws:secretsmanager:<region>:<account-id>:secret:<name>
    try:
        region = secret_arn.split(":")[3]
    except IndexError:
        print_error(f"Could not extract region from secret ARN: {secret_arn}")
        return None

    # Retrieve password from AWS Secrets Manager
    try:
        secrets_client = boto3.client("secretsmanager", region_name=region)
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        password = response["SecretString"]
        print_success("Retrieved admin password from AWS Secrets Manager")
        return password
    except ClientError as e:
        print_error(f"Failed to retrieve password from Secrets Manager: {e}")
        return None
    except Exception as e:
        print_error(f"Unexpected error retrieving password: {e}")
        return None


def login_to_cluster(api_url: str, username: str, password: str) -> bool:
    """Login to cluster using oc CLI and return kubeconfig path."""
    print_info(f"Logging into cluster at {api_url}...")

    # Try oc login
    try:
        # First try without insecure skip
        result = subprocess.run(
            ["oc", "login", api_url, "--username", username, "--password", password, "--insecure-skip-tls-verify=false"],
            capture_output=True,
            text=True,
            timeout=60
        )
        if result.returncode != 0:
            # Try with insecure skip
            result = subprocess.run(
                ["oc", "login", api_url, "--username", username, "--password", password, "--insecure-skip-tls-verify=true"],
                capture_output=True,
                text=True,
                timeout=60
            )
        if result.returncode == 0:
            print_success("Successfully logged into cluster")
            return True
        else:
            print_error(f"Login failed: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print_error("Login timed out")
        return False
    except FileNotFoundError:
        print_error("oc CLI not found. Please install OpenShift CLI")
        return False


def get_k8s_client() -> Tuple[Optional[client.ApiClient], Optional[config.Configuration]]:
    """Get Kubernetes client using kubeconfig from oc login."""
    try:
        # Load kubeconfig (oc login updates ~/.kube/config)
        kubeconfig_path = os.path.expanduser("~/.kube/config")
        if not os.path.exists(kubeconfig_path):
            print_error(f"Kubeconfig not found at {kubeconfig_path}. Run 'oc login' first.")
            return None, None

        # Load kubeconfig
        config.load_kube_config(config_file=kubeconfig_path)
        configuration = client.Configuration.get_default_copy()
        api_client = client.ApiClient(configuration)
        return api_client, configuration
    except Exception as e:
        print_error(f"Failed to load kubeconfig: {e}")
        return None, None


def check_cluster_deployed(api_client: client.ApiClient) -> bool:
    """Check if cluster is accessible."""
    print_info("Checking cluster accessibility...")
    try:
        v1 = client.CoreV1Api(api_client)
        v1.get_api_resources()
        print_success("Cluster is accessible")
        return True
    except ApiException as e:
        print_error(f"Cluster not accessible: {e}")
        return False
    except Exception as e:
        print_error(f"Unexpected error checking cluster: {e}")
        return False


def check_gitops_operator(api_client: client.ApiClient) -> bool:
    """Check if GitOps operator is deployed."""
    print_info("Checking GitOps operator deployment...")

    namespace = "openshift-gitops"
    apps_v1 = client.AppsV1Api(api_client)

    try:
        # Check if namespace exists
        v1 = client.CoreV1Api(api_client)
        try:
            v1.read_namespace(name=namespace)
        except ApiException as e:
            if e.status == 404:
                print_error(f"Namespace '{namespace}' not found")
                return False
            raise

        # Check for GitOps operator deployment
        deployments = apps_v1.list_namespaced_deployment(namespace=namespace)
        gitops_deployments = [d for d in deployments.items if "gitops" in d.metadata.name.lower()]

        if not gitops_deployments:
            print_error(f"No GitOps deployments found in namespace '{namespace}'")
            return False

        # Check if deployments are ready
        all_ready = True
        for deployment in gitops_deployments:
            name = deployment.metadata.name
            ready_replicas = deployment.status.ready_replicas or 0
            replicas = deployment.spec.replicas or 0

            if ready_replicas < replicas:
                print_warning(f"Deployment '{name}' not ready ({ready_replicas}/{replicas} replicas)")
                all_ready = False
            else:
                print_success(f"Deployment '{name}' is ready ({ready_replicas}/{replicas} replicas)")

        if not all_ready:
            print_warning("Some GitOps deployments are not ready yet")
            return False

        print_success("GitOps operator is deployed and ready")
        return True

    except ApiException as e:
        print_error(f"Failed to check GitOps operator: {e}")
        return False
    except Exception as e:
        print_error(f"Unexpected error checking GitOps operator: {e}")
        return False


def check_applicationset(api_client: client.ApiClient, expected_name: str = "cluster-config-applicationset") -> bool:
    """Check if ApplicationSet from cluster-config is deployed."""
    print_info(f"Checking ApplicationSet '{expected_name}'...")

    namespace = "openshift-gitops"

    try:
        # Use CustomObjectsApi for ApplicationSet (CRD)
        custom_api = client.CustomObjectsApi(api_client)
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applicationsets"

        # List ApplicationSets in namespace
        try:
            appsets = custom_api.list_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural
            )
        except ApiException as e:
            if e.status == 404:
                print_error(f"ApplicationSet CRD not found. GitOps may not be fully installed.")
                return False
            raise

        items = appsets.get("items", [])
        if not items:
            print_error(f"No ApplicationSets found in namespace '{namespace}'")
            return False

        # Find the expected ApplicationSet
        found_appset = None
        for appset in items:
            name = appset.get("metadata", {}).get("name", "")
            if expected_name in name.lower():
                found_appset = appset
                break

        if not found_appset:
            print_warning(f"ApplicationSet '{expected_name}' not found")
            print_info(f"Found ApplicationSets: {[item.get('metadata', {}).get('name') for item in items]}")
            return False

        appset_name = found_appset.get("metadata", {}).get("name")
        print_success(f"ApplicationSet '{appset_name}' found")

        # Check ApplicationSet status
        status = found_appset.get("status", {})
        conditions = status.get("conditions", [])

        if conditions:
            for condition in conditions:
                cond_type = condition.get("type", "")
                cond_status = condition.get("status", "")
                cond_message = condition.get("message", "")

                # For ErrorOccurred condition, False is good (no error), True is bad (error occurred)
                # For other conditions like Ready, True is good, False is bad
                if cond_type == "ErrorOccurred":
                    if cond_status == "False":
                        print_success(f"  Condition '{cond_type}': {cond_message}")
                    else:
                        print_error(f"  Condition '{cond_type}': {cond_message}")
                else:
                    if cond_status == "True":
                        print_success(f"  Condition '{cond_type}': {cond_message}")
                    else:
                        print_warning(f"  Condition '{cond_type}': {cond_status} - {cond_message}")

        # Also check for Applications created by the ApplicationSet
        # List Applications in namespace
        applications_plural = "applications"
        try:
            applications = custom_api.list_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=applications_plural
            )
            app_items = applications.get("items", [])
            if app_items:
                print_info(f"Found {len(app_items)} Application(s) managed by ApplicationSet")
                for app in app_items[:5]:  # Show first 5
                    app_name = app.get("metadata", {}).get("name", "")
                    app_sync_status = app.get("status", {}).get("sync", {}).get("status", "Unknown")
                    app_health_status = app.get("status", {}).get("health", {}).get("status", "Unknown")
                    print_info(f"  - {app_name}: sync={app_sync_status}, health={app_health_status}")
        except ApiException:
            # Applications might not exist yet
            pass

        return True

    except ApiException as e:
        print_error(f"Failed to check ApplicationSet: {e}")
        if e.status == 403:
            print_error("Permission denied. Ensure you have access to ApplicationSet resources.")
        return False
    except Exception as e:
        print_error(f"Unexpected error checking ApplicationSet: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Verify ROSA HCP cluster deployment, GitOps operator, and ApplicationSet"
    )
    parser.add_argument(
        "cluster_name",
        help="Name of the cluster to verify"
    )
    parser.add_argument(
        "--applicationset-name",
        default="cluster-config-applicationset",
        help="Expected ApplicationSet name (default: cluster-config-applicationset)"
    )
    parser.add_argument(
        "--skip-login",
        action="store_true",
        help="Skip oc login (assumes already logged in)"
    )
    args = parser.parse_args()

    print_info(f"Verifying cluster: {args.cluster_name}")
    print()

    # Get Terraform directory
    terraform_dir = get_terraform_dir()
    if not terraform_dir.exists():
        print_error(f"Terraform directory not found: {terraform_dir}")
        sys.exit(1)

    # Get cluster information from Terraform outputs
    print_info("Reading Terraform outputs...")
    api_url = run_terraform_output("api_url", terraform_dir)
    cluster_id = run_terraform_output("cluster_id", terraform_dir)
    cluster_name = run_terraform_output("cluster_name", terraform_dir)

    if not api_url:
        print_error("Could not get api_url from Terraform outputs. Is the cluster deployed?")
        sys.exit(1)

    print_success(f"Cluster API URL: {api_url}")
    if cluster_id:
        print_success(f"Cluster ID: {cluster_id}")
    if cluster_name:
        print_success(f"Cluster Name: {cluster_name}")
    print()

    # Get admin password and login
    if not args.skip_login:
        admin_password = get_admin_password(terraform_dir)
        if not admin_password:
            print_error("Could not retrieve admin password")
            sys.exit(1)

        if not login_to_cluster(api_url, "admin", admin_password):
            print_error("Failed to login to cluster")
            sys.exit(1)
        print()
    else:
        print_info("Skipping login (assuming already logged in)")

    # Get Kubernetes client
    api_client, config = get_k8s_client()
    if not api_client:
        print_error("Failed to get Kubernetes client")
        sys.exit(1)
    print()

    # Run verification checks
    checks_passed = 0
    checks_total = 3

    # Check 1: Cluster accessibility
    if check_cluster_deployed(api_client):
        checks_passed += 1
    print()

    # Check 2: GitOps operator
    if check_gitops_operator(api_client):
        checks_passed += 1
    print()

    # Check 3: ApplicationSet
    if check_applicationset(api_client, args.applicationset_name):
        checks_passed += 1
    print()

    # Summary
    print("=" * 60)
    if checks_passed == checks_total:
        print_success(f"All checks passed ({checks_passed}/{checks_total})")
        sys.exit(0)
    else:
        print_error(f"Some checks failed ({checks_passed}/{checks_total} passed)")
        sys.exit(1)


if __name__ == "__main__":
    main()
