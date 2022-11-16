DNSIP=$1                                             # 192.168.1.2
DIR=$(echo $1 | cut -d '.' -f-3)                     # 192.168.1
REV=$(echo $1 | tac -s. | tail -1 | cut -d '.' -f-3) # 1.168.192
ZONA=$2                                              # aula104.local

# https://serverfault.com/questions/85161/should-i-use-etc-bind-zones-or-var-cache-bind
# /var/lib/bind/ - master and dynamic zones
# /var/cache/bind/ - secondary zones
# /etc/bind/ - zones that should not change for the lifetime of the server.

apt-get update
apt-get install -y bind9 bind9utils bind9-doc
 
cat <<EOF >/etc/bind/named.conf.options
acl "allowed" {
    $DIR.0/24;
};

options {
    directory "/var/cache/bind";
    dnssec-validation auto;  // default

    listen-on-v6 { any; };
    forwarders { 1.1.1.1;  1.0.0.1;  };
};
EOF

cat <<EOF >/etc/bind/named.conf.local
zone $ZONA {
        type master;
        file "/var/lib/bind/$ZONA";
        };
zone "$REV.in-addr.arpa" {
        type master;
        file "/var/lib/bind/$DIR.rev";
        };
EOF

cat <<EOF >/var/lib/bind/$ZONA
\$TTL 3600      ; Este es el tiempo, en segundos, que un registro de recurso de zona es válido
$ZONA.     IN      SOA     ns.$ZONA. santi.$ZONA. (
    3           ; n <serial-number> Un valor incrementado cada vez que se cambia el archivo de zona 
    7200        ; 2 horas <time-to-refresh> tiempo de espera de un esclavo antes de preguntar al maestro si se han realizado cambios
    3600        ; 1 hora <time-to-retry>  tiempo de espera antes de emitir una petición de actualización, si el maestro no responde.
    604800      ; 1 semana <time-to-expire> Tiempo que guarda la zona si el servidor maestro no ha respondido. 
    86400 )     ; 1 día <minimum-TTL> Tiempo que otros servidores de nombres guardan en caché la información de zona.

; Registro NameServer de la zona, el cual anuncia los nombres de servidores con autoridad.
$ZONA.          IN      NS      ns.$ZONA. ; debe ser un FQDN.

; Registros Address FQDN y no FQDN
ns.$ZONA.       IN      A       $DNSIP
nginx           IN      A       $DIR.10
apache1.$ZONA.  IN      A       $DIR.11
apache2         IN      A       $DIR.12

; Registros ALIAS FQDN y no FQDN
sv1             IN      CNAME   apache1
sv2             IN      CNAME   apache2
ns1.$ZONA.      IN      CNAME   ns
ns2.$ZONA.      IN      CNAME   ns
proxy           IN      CNAME   nginx
balancer        IN      CNAME   nginx
EOF

cat <<EOF >/var/lib/bind/$DIR.rev
\$ttl 3600
$REV.in-addr.arpa.  IN      SOA     ns.$ZONA. santi.$ZONA. (
    3
    7200
    3600
    604800
    86400 )
; Registros NS
$REV.in-addr.arpa.  IN      NS      ns.$ZONA.

; Registros PUNTEROS
2   IN  PTR dns
10  IN  PTR nginx
11  IN  PTR apache1
12  IN  PTR apache2
EOF

cp /etc/resolv.conf{,.bak}
cat <<EOF >/etc/resolv.conf
nameserver 127.0.0.1
domain $ZONA
EOF

named-checkconf
named-checkconf /etc/bind/named.conf.options
named-checkzone $ZONA /var/lib/bind/$ZONA
named-checkzone $REV.in-addr.arpa /var/lib/bind/$DIR.rev
sudo systemctl restart bind9
