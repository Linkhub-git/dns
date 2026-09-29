#!/usr/bin/env python3
"""Valida zonas/*.yaml antes de que Terraform toque nada. Sale con 1 si hay errores."""
import ipaddress, re, sys, pathlib
import yaml

TIPOS = {"A", "AAAA", "CNAME", "TXT", "NS", "CAA", "MX"}
# Etiquetas con "_" al principio (p. ej. _dmarc, brevo1._domainkey) son de servicio: solo TXT/CNAME.
ETIQUETA = re.compile(r"^(\*|_?[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)$")
FQDN = re.compile(r"^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+$")
errores = []

def err(archivo, i, msg):
    errores.append(f"{archivo} registro #{i + 1}: {msg}")

for archivo in sorted(pathlib.Path("zonas").glob("*.yaml")):
    datos = yaml.safe_load(archivo.read_text()) or {}
    regs = datos.get("registros") or []
    vistos = {}
    for i, r in enumerate(regs):
        nombre, tipo = str(r.get("nombre", "")).lower(), str(r.get("tipo", "")).upper()
        valores, ttl = r.get("valores") or [], r.get("ttl", 300)
        if not nombre or nombre in ("@", "."):
            err(archivo, i, "el apex (app.linkhub.ai) no se toca desde aquí")
        elif not all(ETIQUETA.match(p) for p in nombre.split(".")) or "*" in nombre.split(".")[1:]:
            err(archivo, i, f"nombre inválido: {nombre!r} (minúsculas, dígitos y guiones; * solo al principio)")
        if any(p.startswith("_") for p in nombre.split(".")) and tipo not in ("TXT", "CNAME"):
            err(archivo, i, "los nombres con '_' (_dmarc, _domainkey...) solo pueden ser TXT o CNAME")
        if tipo not in TIPOS:
            err(archivo, i, f"tipo no permitido: {tipo!r} (permitidos: {', '.join(sorted(TIPOS))})")
        if not r.get("dueno"):
            err(archivo, i, "falta 'dueno'")
        if not r.get("nota"):
            err(archivo, i, "falta 'nota'")
        if not isinstance(ttl, int) or not 300 <= ttl <= 86400:
            err(archivo, i, "ttl entre 300 y 86400")
        if not valores:
            err(archivo, i, "sin valores")
        clave = (nombre, tipo)
        if clave in vistos:
            err(archivo, i, f"repetido con el registro #{vistos[clave] + 1} (mismo nombre y tipo: junta los valores)")
        vistos[clave] = i
        for v in valores:
            v = str(v)
            if tipo == "A":
                try: ipaddress.IPv4Address(v)
                except ValueError: err(archivo, i, f"IPv4 inválida: {v}")
            elif tipo == "AAAA":
                try: ipaddress.IPv6Address(v)
                except ValueError: err(archivo, i, f"IPv6 inválida: {v}")
            elif tipo in ("CNAME", "NS") and not FQDN.match(v):
                err(archivo, i, f"{tipo} debe ser un nombre completo terminado en punto: {v}")
        if tipo == "CNAME" and len(valores) != 1:
            err(archivo, i, "un CNAME lleva exactamente un valor")
    nombres_cname = {n for (n, t) in vistos if t == "CNAME"}
    for (n, t), i in vistos.items():
        if n in nombres_cname and t != "CNAME":
            err(archivo, i, f"{n} ya tiene CNAME: no puede tener otros registros")
    nombres_ns = {n for (n, t) in vistos if t == "NS"}
    for (n, t), i in vistos.items():
        if t != "NS" and any(n == d or n.endswith("." + d) for d in nombres_ns):
            err(archivo, i, f"{n} está dentro de una subzona delegada: va en esa subzona, no aquí")

if errores:
    print("\n".join(errores)); sys.exit(1)
print("OK")
