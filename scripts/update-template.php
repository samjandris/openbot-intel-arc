<?php
// Create a private proposed template; only deployment copies it into dockerMan.
if ($argc !== 6) { fwrite(STDERR, "Usage: update-template.php INPUT OUTPUT IMAGE DEVICE GID\n"); exit(2); }
[$program, $input, $output, $image, $device, $gid] = $argv;
if (!preg_match('#^/dev/dri/renderD[0-9]+$#', $device) || !ctype_digit($gid)) exit(2);
$xml = simplexml_load_file($input);
if (!$xml || (string)$xml->Name !== 'openbot' || (string)$xml->Privileged !== 'false') exit(1);
$extra = (string)$xml->ExtraParams;
if (str_contains($extra, '--device') || str_contains($extra, '--group-add')) {
    fwrite(STDERR, "Existing device/group configuration requires manual review.\n"); exit(1);
}
if (!str_contains($extra, '--security-opt=seccomp=/mnt/user/appdata/openbot/seccomp.json') ||
    !str_contains($extra, '--security-opt=no-new-privileges:true')) exit(1);
$xml->Repository = $image;
$xml->ExtraParams = $extra . ' --group-add=' . $gid;
$config = $xml->addChild('Config', $device);
foreach (['Name'=>'Intel Arc A380 render device','Target'=>$device,'Default'=>$device,'Mode'=>'rw',
          'Description'=>'Agent video encoding through VA-API; identified as PCI 0000:2b:00.0.',
          'Type'=>'Device','Display'=>'always','Required'=>'true','Mask'=>'false'] as $k=>$v) $config->addAttribute($k,$v);
if ($xml->asXML($output) === false) exit(1);
chmod($output, 0600);
