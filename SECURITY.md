# Security Policy

## Public repository boundary

This repository contains demonstration code only. Do not commit:

- API keys, access keys, service-account JSON, private keys or tokens;
- real DataWorks workspace IDs, MaxCompute projects, endpoints or internal URLs;
- production table schemas, ETL jobs, business definitions or operational reports;
- customer, employee, order, payment, shop or logistics data.

## Configuration

Runtime integrations must load credentials from environment variables or an external secret manager. Example values must use unmistakable placeholders and must never be valid credentials.

## Reporting

If a secret is committed, revoke or rotate it first. Removing it from the latest commit is not sufficient because Git history retains previous versions.
