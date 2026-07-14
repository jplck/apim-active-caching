"""Runtime secret resolution for the refresher.

The Workday ISU credentials are resolved when the cron job actually runs, not
when the Container App is created. This deliberately avoids the platform reading
a Key Vault reference at *create* time (which races against RBAC propagation for
a freshly-created managed identity and fails the job create). By the time the
cron fires, the refresher identity's ``Key Vault Secrets User`` grant is long
effective, so the read is reliable.

Resolution order for each credential:
  1. A direct environment variable (e.g. ``WORKDAY_USERNAME``) if set/non-empty
     -- handy for local runs and tests, no Key Vault call.
  2. Otherwise fetch it from Key Vault using the app's managed identity
     (``DefaultAzureCredential`` + ``AZURE_CLIENT_ID``) from ``KEY_VAULT_URI``
     under the given secret name.
"""
from __future__ import annotations

import os
from functools import lru_cache
from typing import Optional

from azure.identity import DefaultAzureCredential


@lru_cache(maxsize=1)
def _secret_client():
    """Build a cached Key Vault SecretClient bound to the app's identity."""
    vault_uri = os.environ.get("KEY_VAULT_URI")
    if not vault_uri:
        raise RuntimeError(
            "KEY_VAULT_URI is not set and the credential is not provided "
            "directly via the environment."
        )
    # Imported lazily so environments that inject creds directly (and never
    # install azure-keyvault-secrets) don't pay for the import.
    from azure.keyvault.secrets import SecretClient

    client_id = os.environ.get("AZURE_CLIENT_ID")
    credential = (
        DefaultAzureCredential(managed_identity_client_id=client_id)
        if client_id
        else DefaultAzureCredential()
    )
    return SecretClient(vault_url=vault_uri, credential=credential)


def resolve(env_name: str, secret_name: str) -> str:
    """Resolve a secret from the environment, falling back to Key Vault.

    ``env_name`` is the direct override variable (e.g. ``WORKDAY_USERNAME``);
    ``secret_name`` is the Key Vault secret name (e.g. ``workday-username``).
    """
    direct: Optional[str] = os.environ.get(env_name)
    if direct:
        return direct
    return _secret_client().get_secret(secret_name).value
