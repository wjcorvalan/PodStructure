#!/bin/bash
# Script para configurar directorios y almacenamiento de Podman para un usuario

# Verificar si se pasó un usuario como parámetro
if [ -n "$1" ]; then
    USER="$1"
else
    # Solicitar nombre de usuario si no se pasó como parámetro
    read -p "Ingrese el nombre de usuario: " USER
    
    # Verificar que se ingresó un usuario
    if [ -z "$USER" ]; then
        echo "Error: Debe ingresar un nombre de usuario"
        echo "Uso: $0 [nombre_usuario]"
        exit 1
    fi
fi

# Verificar que el usuario existe en el sistema
if ! id "$USER" &>/dev/null; then
    echo "Error: El usuario '$USER' no existe en el sistema"
    exit 1
fi

# Verificar que el servidor tiene la estructura base profesional
for dir in /srv/podman /srv/compose /srv/data; do
    if [ ! -d "$dir" ]; then
        echo "ERROR: La carpeta base $dir no existe. Ejecute la configuración inicial primero."
        exit 1
    fi
done

# Obtener el UID del usuario
USER_UID=$(id -u "$USER")

echo "==== Configuración de Podman para usuario: $USER (UID: $USER_UID) ===="
echo ""

echo "==== Paso 1: Activar persistencia (Linger) para $USER ===="
# Esto crea la sesión del usuario automáticamente
sudo loginctl enable-linger $USER

# Verificar y esperar a que se cree /run/user/$USER_UID
echo "Esperando a que se inicialice la sesión del usuario..."
TIMEOUT=10
COUNTER=0
while [ ! -d "/run/user/$USER_UID" ] && [ $COUNTER -lt $TIMEOUT ]; do
    sleep 1
    COUNTER=$((COUNTER + 1))
done

if [ ! -d "/run/user/$USER_UID" ]; then
    echo "ADVERTENCIA: /run/user/$USER_UID no se creó automáticamente"
    echo "Intentando crear manualmente..."
    sudo mkdir -p /run/user/$USER_UID
    sudo chown $USER:$USER /run/user/$USER_UID
    sudo chmod 700 /run/user/$USER_UID
fi

echo "✓ Sesión de usuario inicializada"
sudo loginctl show-user $USER | grep Linger

echo ""
echo "==== Paso 2: Detener servicios de Podman existentes (si los hay) ===="
# Intentar detener servicios existentes (puede que no existan en usuario nuevo)
sudo -u $USER bash -c "podman pod stop --all 2>/dev/null || true"
sudo -u $USER bash -c "podman stop --all 2>/dev/null || true"
sudo -u $USER bash -c "podman rm --all --force 2>/dev/null || true"
sudo -u $USER bash -c "podman pod rm --all --force 2>/dev/null || true"

# Detener servicios systemd si existen
sudo systemctl --user -M $USER@ stop podman.socket 2>/dev/null || true
sudo systemctl --user -M $USER@ stop podman.service 2>/dev/null || true

sleep 2

echo ""
echo "==== Paso 3: Crear estructura de directorios ===="

# Crear directorios
echo "Creando directorios en /srv/..."
sudo mkdir -p /srv/podman/$USER/storage /srv/compose/$USER /srv/data/$USER

# Cambiar propietario de los directorios
echo "Configurando permisos de propietario..."
sudo chown -R $USER:$USER /srv/podman/$USER /srv/compose/$USER /srv/data/$USER

# Configurar permisos
echo "Configurando permisos de acceso..."
sudo chmod -R 700 /srv/podman/$USER /srv/compose/$USER /srv/data/$USER

# Crear directorio de configuración
echo "Creando directorios de configuración..."
sudo mkdir -p /home/$USER/.config/containers/systemd/

echo ""
echo "==== Paso 4: Generar archivo de configuración storage.conf ===="
sudo tee /home/$USER/.config/containers/storage.conf > /dev/null <<EOF
[storage]
  driver = "overlay"
  runroot = "/run/user/$USER_UID/containers"
  graphroot = "/srv/podman/$USER/storage"
  [storage.options.overlay]
  mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Cambiar el dueño de la carpeta
sudo chown -R $USER:$USER /home/$USER/.config
echo "✓ Archivo creado: /home/$USER/.config/containers/storage.conf"

echo ""
echo "==== Paso 5: Limpiar entorno anterior (si existe) ===="

# Eliminar directorios antiguos si existen
if [ -d "/home/$USER/.local/share/containers" ]; then
    echo "Eliminando /home/$USER/.local/share/containers..."
    # Limpiar posibles montajes antes de eliminar
    sudo umount -l /home/$USER/.local/share/containers/storage/overlay 2>/dev/null || true
    sudo rm -rf /home/$USER/.local/share/containers
fi

if [ -d "/home/$USER/.cache/containers" ]; then
    echo "Eliminando /home/$USER/.cache/containers..."
    sudo rm -rf /home/$USER/.cache/containers
fi

# Limpiar posibles montajes en run
sudo umount -l /run/user/$USER_UID/containers/storage/overlay 2>/dev/null || true

echo ""
echo "==== Paso 6: Inicializar Podman con nueva configuración ===="
# Reset de podman, filtrando mensajes innecesarios
sudo -u $USER bash -c "cd /tmp && podman system reset --force 2>&1" | \
    grep -v -E 'config file exists|Remove this file|no such file or directory|shutting down container storage' || true

sleep 2

echo ""
echo "==== Paso 7: Verificación final ===="
echo "Verificando configuración de Podman..."
if sudo -u $USER bash -c "cd /tmp && podman info 2>/dev/null" > /dev/null; then
    echo "✓ Podman inicializado correctamente"
    echo ""
    sudo -u $USER bash -c "cd /tmp && podman info 2>/dev/null | grep -E 'graphRoot|runRoot|graphDriverName'"
else
    echo "⚠ Advertencia: Podman no respondió correctamente"
    echo "Esto puede ser normal en la primera ejecución"
fi

echo ""
echo "=========================================="
echo "✓ CONFIGURACIÓN COMPLETADA"
echo "=========================================="
echo "Usuario: $USER (UID: $USER_UID)"
echo ""
echo "Directorios creados:"
echo "  • Storage:  /srv/podman/$USER/storage"
echo "  • Compose:  /srv/compose/$USER"
echo "  • Data:     /srv/data/$USER"
echo ""
echo "Configuración:"
echo "  • Config:   /home/$USER/.config/containers/storage.conf"
echo "  • Linger:   ✓ Activado"
echo "  • RunRoot:  /run/user/$USER_UID/containers"
echo ""
echo "Comandos de verificación:"
echo "  sudo -u $USER podman info"
echo "  sudo -u $USER podman run --rm hello-world"
echo ""
