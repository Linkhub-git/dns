# DNS de app.linkhub.ai

Subdominios de las aplicaciones de linkhub, como código. Nadie entra a Webempresa ni a la
consola de Cloud DNS: todo cambio es un pull request a este repo.

- **Producción:** `<producto>.app.linkhub.ai` (p. ej. `crm.app.linkhub.ai`)
- **Otros entornos:** `<entorno>.<producto>.app.linkhub.ai` (p. ej. `dev.crm.app.linkhub.ai`, `pre.crm.app.linkhub.ai`).
  Todo lo de un producto cuelga de `<producto>.app.linkhub.ai`.

`linkhub.ai` (la web y el correo de la empresa) sigue en Webempresa y **no se toca desde
aquí**. Webempresa solo delega `app.linkhub.ai` a Cloud DNS (proyecto `linkhub-dns`, zona
`app-linkhub-ai`).

## Cómo pedir un subdominio

1. Crea una rama y edita `zonas/app.linkhub.ai.yaml`. Añade tu registro:
   ```yaml
     - nombre: dev.gestion          # -> dev.gestion.app.linkhub.ai
       tipo: A
       ttl: 300
       valores: [34.120.10.20]      # IP de tu balanceador
       dueno: equipo-gestion
       nota: Panel de la plataforma de gestión (dev)
   ```
2. Abre un pull request a `main`. El CI valida el archivo y comenta el **plan**: qué se va
   a crear, cambiar o borrar. Revísalo.
3. Lo aprueba Ángel o Mario (`CODEOWNERS`). Al hacer merge se aplica solo, en un par de
   minutos.

Tipos permitidos: `A`, `AAAA`, `CNAME`, `TXT`, `NS`, `CAA`, `MX`. El validador rechaza
nombres inválidos, duplicados, un CNAME con más registros, registros sin `dueno` o `nota`
y cualquier intento de tocar el apex (`app.linkhub.ai`).

### Productos grandes: su propia subzona

Si tu producto necesita muchos nombres o cambiarlos a menudo (p. ej. uno por cliente,
`<cliente>.dev.crm.app.linkhub.ai`), no los pongas aquí uno a uno. Crea una zona de Cloud
DNS en **el proyecto de tu producto** y pide aquí solo la delegación:

```bash
gcloud dns managed-zones create dev-crm --project=<tu-proyecto> \
  --dns-name=dev.crm.app.linkhub.ai. --description="CRM dev" --visibility=public
gcloud dns managed-zones describe dev-crm --project=<tu-proyecto> --format='value(nameServers)'
```

```yaml
  - nombre: dev.crm
    tipo: NS
    ttl: 3600
    valores: [ns-cloud-b1.googledomains.com., ns-cloud-b2.googledomains.com., ns-cloud-b3.googledomains.com., ns-cloud-b4.googledomains.com.]
    dueno: equipo-crm
    nota: Subzona del CRM en lhcrm-dev
```

A partir del merge, todo lo que cuelga de `dev.crm.app.linkhub.ai` lo gestiona tu equipo en
su proyecto, sin pasar por este repo.

### Certificados

- **Certificate Manager (balanceador de Google):** usa autorización por DNS. Si tu nombre
  está en una subzona tuya, el CNAME `_acme-challenge…` va en tu subzona. Si no, pídelo
  aquí como `CNAME`.
- **Cloud Run con dominio propio / Firebase Hosting:** pide el `A`/`CNAME` que te indique
  la consola, más el `TXT` de verificación si lo pide.

## Cómo funciona

| Pieza | Qué es |
|---|---|
| `zonas/app.linkhub.ai.yaml` | Los registros. La única fuente de verdad. |
| `scripts/validar.py` | Reglas del archivo (corre en cada PR y antes de aplicar). |
| `main.tf` | Terraform: un `google_dns_record_set` por registro. Estado en `gs://linkhub-dns-tfstate`. |
| `.github/workflows/dns.yml` | PR → valida + plan (cuenta `dns-plan`, solo lectura). Push a `main` → aplica (cuenta `dns-apply`). |
| `infra/bootstrap.sh` | Crea cuentas, bucket y Workload Identity Federation. Una vez, un Owner. |

Seguridad:

- GitHub entra sin claves (Workload Identity Federation), restringido por **id numérico**
  del repo y de la organización.
- `dns-plan` solo lee. `dns-apply` solo puede cambiar registros de `app-linkhub-ai` (no
  crear ni borrar zonas, ni tocar nada más del proyecto) y solo la recibe un **push a
  `main`**: un PR, aunque modifique el workflow, no puede aplicar.
- `main` protegida: merge solo por PR con la aprobación de `CODEOWNERS`.
- Los registros que existan en la zona y no estén en el YAML **no se tocan** (Terraform
  solo gestiona los suyos). Si quitas un registro del YAML, se borra en Cloud DNS.

## Probar en local

```bash
pip install pyyaml && python3 scripts/validar.py
terraform fmt -check
```
