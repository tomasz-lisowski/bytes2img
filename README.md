# Bytes to Image
Given a list of hex digits (in ascii), it produces an image in one of the
supported standard image formats.

## How to use
Run the program with a desired configuration e.g. ```bytes2img -t 3 2 ppm
ff000000ff000000ffffff00ffffff000000```, which will produce the desired image in
the current working directory. Alternatively we can specify a file where to read
the bytes from e.g. ```bytes2img -f 24 7 pgm pgm_example.txt```.

**Note:** The example used above was taken from
https://en.wikipedia.org/wiki/Netpbm which describes the Netpbm family of
formats. All the representative examples have been included under
```examples/*.txt``` files.

## Byte Input Format
- Only hex digit characters (0-9, a-f)
- All lower-case
- No whitespace i.e. new line chars, spaces, carriage returns etc...

## Supported Image Output Formats
- **PBM**: Portable BitMap
- **PGM**: Portable GrayMap
- **PPM**: Portable PixMap