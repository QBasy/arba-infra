#!/usr/bin/env python3
"""Собирает VERSIONS.md из envs/*/*/app.yaml: таблица «сервис × окружение».
Источник правды — app.yaml; VERSIONS.md — справочник для людей (CI обновляет его автоматически)."""
import glob, os, sys
import yaml

root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
envs, services, data = [], set(), {}
for path in sorted(glob.glob(os.path.join(root, "envs", "*", "*", "app.yaml"))):
    env, svc = path.split(os.sep)[-3], path.split(os.sep)[-2]
    with open(path, encoding="utf-8") as f:
        d = yaml.safe_load(f) or {}
    if env not in envs:
        envs.append(env)
    services.add(svc)
    data[(svc, env)] = d

order = [e for e in ("dev", "stage", "prod") if e in envs] + [e for e in envs if e not in ("dev", "stage", "prod")]
lines = ["# Версии сервисов по окружениям", "",
         "Файл создаётся скриптом `scripts/render-versions.py` из `envs/*/*/app.yaml`. Руками не править.", "",
         "| Сервис | " + " | ".join(order) + " |",
         "| --- | " + " | ".join("---" for _ in order) + " |"]
for svc in sorted(services):
    cells = []
    for env in order:
        d = data.get((svc, env))
        if not d:
            cells.append("—")
            continue
        dig = str(d.get("imageDigest") or "")[7:19]
        rev = str(d.get("revision") or "")[:7]
        cells.append(f"`{d.get('imageTag')}`<br>`{dig or 'no digest'}`<br>{rev}")
    lines.append(f"| `{svc}` | " + " | ".join(cells) + " |")
lines += ["", "Ячейка: тег образа, первые 12 символов digest, коммит с `.helm/`.", ""]
out = os.path.join(root, "VERSIONS.md")
open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("wrote", out)
