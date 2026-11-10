<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <b>Español</b> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control para macOS: servicio en segundo plano siempre activo con launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Ejecuta **Remote Control** de [Claude Code](https://code.claude.com) (`claude remote-control`) como un servicio de macOS siempre activo en segundo plano (LaunchAgent de launchd). Tu Mac aparece como una **tarjeta de dispositivo** en la pestaña Code de la app de Claude (y en claude.ai/code), así que puedes iniciar sesiones nuevas e independientes desde el móvil en cualquier momento, sin dejar una terminal abierta.

Es un pequeño LaunchAgent más un script supervisor. Arranca al iniciar sesión, reinicia el servidor cuando termina y evita los reinicios en bucle.

> Proyecto comunitario no oficial, sin afiliación ni respaldo de Anthropic.

## Instalación (un solo comando)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

o desde un clon del repositorio:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Opción | Por defecto | Significado |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Directorio donde empiezan las sesiones. Debe ser de **confianza** para Claude Code (ver abajo). No puede ser tu directorio personal. |
| `--name NAME` | el nombre del Mac | Nombre del dispositivo que se muestra en la app |
| `--capacity N` | `10` | Máximo de sesiones simultáneas. Las sesiones inactivas conservan su plaza, así que con el servidor lleno las sesiones nuevas se ignoran en silencio. |
| `--spawn MODE` | `same-dir` | `same-dir` (archivos compartidos) o `worktree` (requiere un repositorio git) |
| `--keep-awake` | desactivado | Mantiene `caffeinate -s` mientras el servidor funciona, para que el Mac no entre en reposo con el cargador conectado. No cambia ningún ajuste de energía del sistema. |

Volver a ejecutar `install.sh` con otras opciones actualiza la instalación en el sitio.

**Antes de instalar:** inicia sesión (`claude auth login`, con una cuenta de claude.ai; las claves de API no funcionan con Remote Control) y marca el directorio de trabajo como de confianza una vez: `cd ~/projects && claude` y acepta el aviso. El instalador comprueba ambas cosas y te dice qué hacer.

## Uso diario

```bash
./install.sh status        # estado del trabajo, configuración y últimas líneas del registro
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Desinstalación (un solo comando)

```bash
./uninstall.sh                       # elimina el trabajo, el script, la configuración y los registros
./uninstall.sh --keep-logs           # conserva los registros
# sin clonar el repositorio:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

Al desinstalar se detienen el servidor y las sesiones que atiende.

## Cómo funciona

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` ejecuta `claude-code-remote-control.sh` con `RunAtLoad` y `KeepAlive`. En cada ciclo el script:

1. espera a la red (hasta 2 min);
2. comprueba `claude auth status`; si no hay sesión iniciada, registra la solución y espera 5 min en lugar de insistir;
3. aplica un retardo tras 3 arranques en una hora (5 min por cada arranque extra, máximo 30), para que un servidor roto no entre en bucle y deje dispositivos fantasma en el móvil;
4. ejecuta `claude remote-control --spawn <modo> --capacity <n> --name <nombre>` en tu directorio de trabajo;
5. considera que está atascado si no hay una conexión HTTPS establecida en 150 s (por ejemplo, un aviso de primer uso invisible) y lo reinicia;
6. registra un latido cada 5 min y, cuando el servidor termina, el código de salida y las últimas líneas de salida.

Antes de nada elimina las variables heredadas `CLAUDE*`, `ANTHROPIC_API_KEY` y `ANTHROPIC_AUTH_TOKEN`, así que nunca toma la identidad de otra sesión.

Todo vive en `~/.local/share/claude-code-remote-control/`. En Ajustes del Sistema > General > Ítems de inicio y extensiones aparece como `claude-code-remote-control.sh` (no como un simple `bash`).

## Límites y notas

- **Reposo.** Un Mac en reposo no es accesible. Usa `--keep-awake` (ejecuta `caffeinate -s` solo mientras el servidor funciona y solo sirve con el cargador conectado) o gestiónalo tú en los ajustes de energía. Esta herramienta nunca cambia los ajustes de energía del sistema. El comportamiento con la tapa cerrada no está verificado.
- **Hay que iniciar sesión tras reiniciar.** Un LaunchAgent se ejecuta dentro de una sesión iniciada; con FileVault y sin inicio de sesión automático, inicia sesión una vez tras reiniciar.
- **Caducidad del inicio de sesión.** Renuévalo con `claude auth login` cuando caduque. El registro muestra la fecha de caducidad en cada arranque.
- **Reiniciar termina las sesiones.** Reiniciar el servidor (o volver a ejecutar `install.sh`, o desinstalar) detiene las sesiones que atiende. Las transcripciones quedan en disco.
- Depende del comportamiento de `claude remote-control` en las versiones actuales de Claude Code; las opciones pueden cambiar.

## Preguntas frecuentes

### ¿Cómo mantengo Claude Code Remote Control en ejecución todo el tiempo en un Mac?

Instala este LaunchAgent. Ejecuta `claude remote-control` en segundo plano, lo arranca al iniciar sesión y lo reinicia cuando termina, de modo que tu Mac sigue disponible como dispositivo en la app de Claude.

### ¿Sigue funcionando `claude remote-control` después de cerrar la terminal o reiniciar?

Por sí solo no: es un proceso en primer plano y se rinde tras unos 10 minutos sin red. Bajo launchd se reinicia automáticamente y arranca en cada inicio de sesión. Tras reiniciar con FileVault hay que iniciar sesión una vez.

### ¿Por qué las sesiones nuevas desde el móvil no responden?

Probablemente el servidor está lleno: las sesiones inactivas conservan su plaza. Mira `Capacity: n/N` en `server.out`, termina las sesiones inactivas o reinstala con un `--capacity` mayor.

### ¿Tiene que estar el Mac despierto?

Sí, un Mac en reposo no es accesible. Instala con `--keep-awake` para mantener `caffeinate -s` mientras el servidor funciona (solo con el cargador conectado) o configúralo en los ajustes de energía.

### ¿Cómo lo desinstalo?

Ejecuta `./uninstall.sh`, o el comando curl con `uninstall`. Elimina el LaunchAgent, el script, la configuración y los registros.

## Desarrollo

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## Licencia

[MIT](LICENSE)
