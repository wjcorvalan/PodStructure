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

# Obtener el UID del usuario
USER_UID=$(id -u "$USER")

echo "Configurando directorios para el usuario: $USER (UID: $USER_UID)"

# Crear directorios
echo "Creando directorios..."
sudo mkdir -p /srv/podman/$USER/storage /srv/compose/$USER /srv/data/$USER

# Cambiar propietario de los directorios
echo "Configurando permisos de propietario..."
sudo chown -R $USER:$USER /srv/podman/$USER /srv/compose/$USER /srv/data/$USER

# Configurar permisos
echo "Configurando permisos de acceso..."
sudo chmod -R 750 /srv/podman/$USER /srv/compose/$USER /srv/data/$USER

# Crear directorio de configuración de containers
echo "Creando directorio de configuración..."
sudo mkdir -p /home/$USER/.config/containers/systemd/

# Crear archivo storage.conf
echo "Generando archivo de configuración storage.conf..."
sudo tee /home/$USER/.config/containers/storage.conf > /dev/null <<EOF
[storage]
  driver = "overlay"
  runroot = "/run/user/$USER_UID/containers"
  graphroot = "/srv/podman/$USER/storage"
  [storage.options.overlay]
  mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Eliminar entorno inicial
echo "Eliminando entorno inicial..."
sudo rm -rf /home/$USER/.local/share/containers
sudo rm -rf /home/$USER/.cache/containers

# Reiniciar podman al usuario 
echo "Reiniciando poddman al usuario $USER"
sudo -u "$USER" podman system reset --force

# Cambiar propietario del directorio .config
echo "Configurando permisos del directorio .config..."
sudo chown -R $USER:$USER /home/$USER/.config

# Verificacion
echo "Verificando Entorno actual"
sudo -u $USER bash -c "cd /tmp && podman info | grep -E 'graphRoot|runRoot|graphDriverName'"

echo ""
echo "✓ Configuración completada exitosamente para el usuario: $USER"
echo "  - Directorios creados en /srv/"
echo "  - Archivo de configuración: /home/$USER/.config/containers/storage.conf"
