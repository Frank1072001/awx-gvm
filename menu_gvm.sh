#!/bin/bash

# Función para mostrar las IPs activas en la red
function discover_ips() {
    nmap -sn 192.168.81.0/24 | grep "Nmap scan report for" | awk '{print $5}'
}

TARGET_NAME=""
SCAN_NAME=""
TEMP_FILE=$(mktemp)

# Menú con dialog para introducir los datos del escaneo
dialog --title "Configuración de Target y Escaneo" \
    --form "Introduce los datos para configurar el escaneo:" \
    15 60 2 \
    "Nombre del Target:" 1 1 "" 1 20 30 0 \
    "Nombre del Escaneo:" 2 1 "" 2 20 30 0 \
    2>$TEMP_FILE

# Leer los datos ingresados por el usuario
TARGET_NAME=$(sed -n '1p' $TEMP_FILE)
SCAN_NAME=$(sed -n '2p' $TEMP_FILE)
rm $TEMP_FILE

# Obtener las IPs activas
IPS=$(discover_ips)

# Verificar si se encontraron IPs
if [ -z "$IPS" ]; then
    dialog --msgbox "No se detectaron IPs activas en la red." 10 60
    exit 1
fi

# Convertir las IPs en el formato adecuado para el menu de dialog
IP_OPTIONS=""
COUNTER=1
for IP in $IPS; do
    IP_OPTIONS="$IP_OPTIONS $COUNTER \"$IP\""
    ((COUNTER++))
done

# Mostrar el menú de selección de IP usando dialog
SELECTED_IP=$(dialog --title "Seleccionar IP del Target" --menu "Selecciona la IP del objetivo desde las siguientes opciones:" 20 70 15 \
    $IP_OPTIONS 2>&1 >/dev/tty)

# Verificar si se seleccionó una IP
if [ -z "$SELECTED_IP" ]; then
    dialog --msgbox "No se seleccionó ninguna IP, abortando." 10 60
    exit 1
fi

# Obtener la IP seleccionada
SELECTED_IP=$(echo "$IPS" | sed -n "${SELECTED_IP}p")

# Mostrar la IP seleccionada
dialog --msgbox "Has seleccionado la IP: $SELECTED_IP" 10 60

# Confirmación final
dialog --title "Confirmación" --yesno "¿Deseas proceder con el escaneo para el target $TARGET_NAME y la tarea $SCAN_NAME?" 10 60
if [ $? -ne 0 ]; then
    echo "Operación cancelada por el usuario."
    exit 1
fi

# Ejecutar el playbook y capturar la salida
PLAYBOOK_OUTPUT=$(mktemp)
echo "Ejecutando el playbook con los siguientes parámetros:" > "$PLAYBOOK_OUTPUT"
echo "target_name=$TARGET_NAME" >> "$PLAYBOOK_OUTPUT"
echo "task_name=$SCAN_NAME" >> "$PLAYBOOK_OUTPUT"
echo "target_ip=$SELECTED_IP" >> "$PLAYBOOK_OUTPUT"

# Ejecutar el playbook y registrar la salida
echo "Ejecutando el playbook..." >> "$PLAYBOOK_OUTPUT"
ansible-playbook -e "target_name=$TARGET_NAME task_name=$SCAN_NAME target_ip=$SELECTED_IP" playbook_gvm.yml | tee -a "$PLAYBOOK_OUTPUT"

# Mostrar la salida del playbook para depuración
dialog --msgbox "Salida del playbook grabada. Revisa el archivo temporal para más detalles." 10 60

# Verificar si el archivo contiene un task_id
TASK_ID=$(grep -oP 'task_id: \K[a-f0-9\-]+' "$PLAYBOOK_OUTPUT")

# Ver la salida de depuración
echo "TASK_ID EXTRAÍDO: $TASK_ID"

# Validar que se haya obtenido el Task ID
if [[ -z "$TASK_ID" ]]; then
    dialog --msgbox "Error: No se pudo obtener el ID de la tarea. Revisa la salida del playbook para detalles." 10 60
    echo "No se encontró task_id en la salida del playbook. Salida completa del playbook:"
    cat "$PLAYBOOK_OUTPUT"  # Mostrar la salida completa para depuración
    exit 1
fi

# Mostrar barra de progreso sincronizada con el escaneo
(
    while true; do
        # Consultar progreso del escaneo desde GVM
        PROGRESS=$(gvm-cli --gmp-username admin --gmp-password 11611961-1693-46cb-8f87-c342fd642dd6 \
            socket --socketpath /run/gvmd/gvmd.sock \
            --xml "<get_tasks task_id='$TASK_ID'/>" | grep -oP '(?<=<progress>)[0-9]+(?=</progress>)')
        
        # Finalizar barra si el progreso llega al 100%
        if [[ -z "$PROGRESS" || "$PROGRESS" -ge 100 ]]; then
            break
        fi

        echo "$PROGRESS"
        sleep 5  # Consultar cada 5 segundos
    done
) | dialog --title "Progreso del Escaneo" --gauge "Ejecutando el escaneo..." 10 70 0

# Mostrar el cuadro de confirmación para saber si el usuario desea recibir el reporte
dialog --title "Descargar Reporte" --yesno "¿Deseas recibir el reporte en formato Excel por correo?" 10 60
if [ $? -eq 0 ]; then
    # Mostrar un cuadro de entrada para obtener el correo electrónico del usuario
    EMAIL=$(dialog --inputbox "Introduce el correo electrónico para enviar el reporte" 10 60 2>&1 >/dev/tty)

    # Validar si se ingresó un correo
    if [ -z "$EMAIL" ]; then
        dialog --msgbox "No se ingresó ningún correo, operación cancelada." 10 60
        exit 1
    fi

    # Llamar al script PHP para generar y enviar el reporte al correo ingresado
    php /home/kali/Desktop/shell/generar_reporte.php --email="$EMAIL" --target_ip="$SELECTED_IP"
fi
