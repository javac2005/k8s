#!/usr/bin/expect  
set timeout 10  
set password [lindex $argv 0]  
set hostname [lindex $argv 1]  
spawn ssh-copy-id -i /root/.ssh/id_rsa.pub root@$hostname
expect {
            #first connect, no public key in ~/.ssh/known_hosts
            "Are you sure you want to continue connecting (yes/no)?" {
            send "yes\r"
            expect "password:"
                send "$password\r"
            }
            #already has public key in ~/.ssh/known_hosts
            "password:" {
                send "$password\r"
            }
            "Now try logging into the machine" {
                #it has authorized, do nothing!
            }
        }
expect eof