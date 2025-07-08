<?php
require __DIR__ . '/vendor/autoload.php';

//require 'vendor/autoload.php';  // Asegúrate de que el path a autoload.php sea correcto

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

// Verificar que el correo fue proporcionado
if ($argc < 3) {
    die("Debe proporcionar el correo electrónico como argumento.\n");
}

// Obtener el correo del usuario
$email = $argv[1];
$email = str_replace('--email=', '', $email);  // Extraer el valor del parámetro --email

$target_ip = $argv[2];
$target_ip = str_replace('--target_ip=', '', $target_ip);

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    die("El correo electrónico proporcionado no es válido.\n");
}

// Validar que la IP sea válida
//if (!filter_var($target_ip, FILTER_VALIDATE_IP)) {
//    die("La IP proporcionada no es válida.\n");
//}

// Conexión a la base de datos
$conn = pg_connect("host=localhost dbname=gvmd user=postgres password=2014563");

if (!$conn) {
    die("Connection failed: " . pg_last_error());
}

// Ejecutar la consulta
$query = "
    SELECT r.host, r.hostname, r.port, n.cve, n.name AS vulnerability_name, r.severity, n.solution
    FROM results r
    JOIN nvts n ON r.nvt = n.oid
    WHERE r.host = '$target_ip'
    AND n.modification_time = (
      SELECT MAX(n2.modification_time)
      FROM nvts n2
      WHERE n2.oid = n.oid
    )
    ORDER BY r.host, r.port;
";

$result = pg_query($conn, $query);

if (!$result) {
    die("Error en la consulta: " . pg_last_error());
}

// Crear un nuevo objeto Spreadsheet
$spreadsheet = new Spreadsheet();
$sheet = $spreadsheet->getActiveSheet();

// Títulos de las columnas
$sheet->setCellValue('A1', 'Host');
$sheet->setCellValue('B1', 'Port');
$sheet->setCellValue('C1', 'CVE');
$sheet->setCellValue('D1', 'Vulnerability Name');
$sheet->setCellValue('E1', 'Severity');
$sheet->setCellValue('F1', 'Solution');

// Escribir los datos
$row = 2;
while ($row_data = pg_fetch_assoc($result)) {
    $sheet->setCellValue('A' . $row, $row_data['hostname']);
    $sheet->setCellValue('B' . $row, $row_data['port']);
    $sheet->setCellValue('C' . $row, $row_data['cve']);
    $sheet->setCellValue('D' . $row, $row_data['vulnerability_name']);
    $sheet->setCellValue('E' . $row, $row_data['severity']);
    $sheet->setCellValue('F' . $row, $row_data['solution']);
    $row++;
}

// Cerrar la conexión a la base de datos
pg_close($conn);

// Crear un escritor de Excel
$writer = new Xlsx($spreadsheet);

// Guardar el archivo Excel temporalmente
$filename = '/tmp/Vulnerabilidades_Detectadas_' . time() . '.xlsx';
$writer->save($filename);

// Enviar el correo con el archivo adjunto

$mail = new PHPMailer(true);
try {
    // Configuración del servidor SMTP de Gmail
    $mail->isSMTP();                                            // Establecer el correo como SMTP
    $mail->Host       = 'smtp.gmail.com';                         // Especificar el servidor SMTP de Gmail
    $mail->SMTPAuth   = true;                                     // Activar autenticación SMTP
    $mail->Username   = 'frank11072001@gmail.com';                      // Tu dirección de correo de Gmail
    $mail->Password   = 'shfxnyiwipbyfrur';       // Tu contraseña de Gmail o la contraseña de aplicación
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;            // Activar cifrado TLS
    $mail->Port       = 587;                                      // Puerto para el servidor SMTP de Gmail
    
    // Remitente y destinatario
    $mail->setFrom('frank11072001@gmail.com', 'MANUUUUUUUUUUUU');
    $mail->addAddress($email);                                     // Dirección de correo a la que se enviará el archivo

    // Contenido del correo
    $mail->isHTML(true);
    $mail->Subject = 'Reporte de Vulnerabilidades';
    $mail->Body    = 'Adjunto encontrarás el reporte de vulnerabilidades detectadas.';

    // Adjuntar el archivo Excel
    $mail->addAttachment($filename);                             // Adjuntar el archivo generado

    // Enviar el correo
    $mail->send();

    echo 'El correo fue enviado correctamente.';
} catch (Exception $e) {
    echo "Hubo un error al enviar el correo. Error: {$mail->ErrorInfo}";
}

// Eliminar el archivo temporal después de enviarlo
unlink($filename);
?>
