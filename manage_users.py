"""
Bulk-create/update Grupo ATE app users from a CSV template.
Usage: python manage_users.py <path_to_csv>  (defaults to plantilla_usuarios.csv)

CSV columns: email, role, cities, password
  - role: "admin" or "user"
  - cities: "all", or a comma-separated list of city codes
            (tj, mex, gdl, ver, hgo, can, mer, qro, cdmx, vhs)
  - password: required only when creating a brand-new user; ignored for
              existing users (their password is never touched by this script)

Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in a local .env file
(see .env.example). The service role key must never be committed or shared —
it bypasses RLS entirely.
"""

import csv
import os
import sys

from dotenv import load_dotenv
from supabase import create_client, Client

VALID_CITIES = {'tj', 'mex', 'gdl', 'ver', 'hgo', 'can', 'mer', 'qro', 'cdmx', 'vhs'}
VALID_ROLES = {'admin', 'user'}


def validate_row(row):
    errors = []
    email = (row.get('email') or '').strip()
    role = (row.get('role') or '').strip()
    cities = (row.get('cities') or '').strip()

    if not email or '@' not in email:
        errors.append(f"invalid email: '{email}'")
    if role not in VALID_ROLES:
        errors.append(f"invalid role '{role}' (must be admin or user)")
    if cities != 'all':
        codes = [c.strip() for c in cities.split(',') if c.strip()]
        if not codes:
            errors.append("cities is empty (use 'all' or a comma-separated city list)")
        bad = [c for c in codes if c not in VALID_CITIES]
        if bad:
            errors.append(f"unknown city code(s): {', '.join(bad)}")

    return email, role, cities, errors


def main():
    load_dotenv()
    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
    if not url or not key:
        print("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY. Copy .env.example to .env and fill in the service role key from the Supabase dashboard (Project Settings > API).")
        sys.exit(1)

    csv_path = sys.argv[1] if len(sys.argv) > 1 else 'plantilla_usuarios.csv'
    print(f"Reading {csv_path}")

    with open(csv_path, encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

    supabase: Client = create_client(url, key)

    print("Fetching existing users...")
    existing = {}
    page = 1
    while True:
        result = supabase.auth.admin.list_users(page=page, per_page=200)
        if not result:
            break
        for u in result:
            existing[u.email.lower()] = u
        if len(result) < 200:
            break
        page += 1
    print(f"  {len(existing)} existing user(s) found.")

    created, updated, skipped = 0, 0, 0

    for row in rows:
        email, role, cities, errors = validate_row(row)
        if errors:
            print(f"  SKIP {email or '(no email)'}: {'; '.join(errors)}")
            skipped += 1
            continue

        app_metadata = {'role': role, 'cities': cities}
        existing_user = existing.get(email.lower())

        if existing_user:
            supabase.auth.admin.update_user_by_id(existing_user.id, {'app_metadata': app_metadata})
            print(f"  UPDATED {email} -> role={role}, cities={cities}")
            updated += 1
        else:
            password = (row.get('password') or '').strip()
            if not password:
                print(f"  SKIP {email}: new user but no password provided")
                skipped += 1
                continue
            supabase.auth.admin.create_user({
                'email': email,
                'password': password,
                'email_confirm': True,
                'app_metadata': app_metadata,
            })
            print(f"  CREATED {email} -> role={role}, cities={cities}")
            created += 1

    print("\n" + "=" * 50)
    print(f"Created: {created}  Updated: {updated}  Skipped: {skipped}")
    print("=" * 50)


if __name__ == '__main__':
    main()
