#!/usr/bin/env python3
"""Read the ISO 9660 volume identifier without parsing localized tool output."""
import re
import sys


def read_label(path):
    with open(path, 'rb') as image:
        # ECMA-119 volume descriptors start at logical sector 16 (2048 bytes).
        for sector in range(16, 256):
            image.seek(sector * 2048)
            descriptor = image.read(2048)
            if len(descriptor) != 2048 or descriptor[1:6] != b'CD001' or descriptor[6] != 1:
                raise ValueError('invalid ISO 9660 volume descriptor')
            if descriptor[0] == 1:
                label = descriptor[40:72].decode('ascii').rstrip(' ')
                if not re.fullmatch(r'[A-Za-z0-9_-]{1,32}', label):
                    raise ValueError('unsupported ISO volume label')
                return label
            if descriptor[0] == 255:
                break
    raise ValueError('ISO has no primary volume descriptor')


if __name__ == '__main__':
    try:
        print(read_label(sys.argv[1]))
    except (OSError, ValueError, IndexError) as error:
        sys.exit(str(error))
