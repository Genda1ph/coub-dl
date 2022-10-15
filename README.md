# Coub downloader

Since Coub started blocking coubs, I've slapped together a tool to save coubs locally in highest quality.

## Requirements

- Ruby (tested using `ruby 2.7.4p191 (2021-07-07 revision a21a3b7d23) [x86_64-linux-gnu]`)
- Nokogiri
- FFmpeg (tested using `ffmpeg version 4.3.4-0+deb11u1 Copyright (c) 2000-2021 the FFmpeg developers`)

## Usage

### Simple

`./download.rb -u URL`

Provided a valid coub URL will create a directory with coub permalink in current directory, download coub metadata, video, audio and join them using FFmpeg.

### Batch

```
cat links.txt | while read url; do
    ./download.rb -d ~/Downloads/coubs -u "$url"
    sleep 0.5
done
```

Given coub links (one per line) in `links.txt`, will attempt to download all of them to `~/Downloads/coubs/$permalink`.

## Caveats:

Unless script gets a valid JSON from a page, it will not do anything.

Everything is cached: JSON is saved as `$permalink/coub.json`, audio as `$permalink/audio.ext`, video as `$permalink/video.ext` and will not be downloaded again if sizes match what's in JSON.

The script will throw an error if output file (`$permalink/coub.mp4`) already exists. In this case, simply nuke the output file or whole directory and try again.

# License

License: AGPL 3.0.

