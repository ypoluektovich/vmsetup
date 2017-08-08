import pexpect
import time


def new_console(vm):
    return pexpect.spawn('virsh -c qemu:///system console ' + vm)


def expect_prompt(child):
    child.expect('prompt>', timeout=None)


def login_and_set_prompt(child):
    child.sendline('')
    child.expect('localhost login: ')
    child.sendline('root')
    i = child.expect(['Password: ', 'localhost:~# '])
    if i == 0:
        child.sendline('1')
        child.expect('localhost:~# ')
    child.sendline('export PS1="prompt\>"')
    expect_prompt(child)
    print('logged in')


def upload_file(child, name):
    child.sendline('rm -f ' + name)
    child.sendline('vi ' + name)
    time.sleep(1)
    child.send('i')

    with open('upload/' + name, 'r') as f:
        for line in f:
            child.send(line)

    time.sleep(1)
    child.sendcontrol('{')
    time.sleep(1)
    child.sendline(':wq')
    expect_prompt(child)
    time.sleep(1)

    print('uploaded ' + name)
