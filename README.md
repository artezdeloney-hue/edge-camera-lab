# Edge Camera Lab

A small edge video pipeline built and debugged on one Linux box: a USB camera
streams over RTSP into a containerized relay server, and a health check script
reports whether the stream is up and, if not, why.

## Architecture

```
C920 USB camera --> ffmpeg (runs as service user camwatch)
                      |  RTSP control: TCP 8554
                      |  RTP video:    UDP 8000
                      v
                 MediaMTX in Docker (host networking)
                      |
          +-----------+------------+
          v                        v
   ffplay / VLC viewer     check-stream.sh health check
```

## Hardware and software

- Ubuntu 26.04 LTS, Ryzen 9 9950X3D, RTX 5080
- Logitech C920 PRO HD webcam (USB, MJPG 720p30)
- Docker, MediaMTX (`bluenviron/mediamtx`), ffmpeg / ffprobe

## Setup

**1. Relay server**

```bash
sudo docker run -d --name rtsp-server --network host --restart always \
  -e TZ=America/Los_Angeles \
  -v /usr/share/zoneinfo:/usr/share/zoneinfo:ro \
  bluenviron/mediamtx:latest
```

Host networking lets the UDP video through without port mapping. The image has
no time zone files, so the host's are mounted read-only.

**2. Service user for the camera (least privilege)**

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin camwatch
sudo usermod -aG video camwatch
```

The camera (`/dev/video0`) is `root:video`, mode 660. A desktop login gets
extra access through an ACL; a background service does not. Tested by proving
camwatch got "Permission denied" first, then adding the `video` group.

**3. Stream the camera**

```bash
sudo -u camwatch ffmpeg -hide_banner -f v4l2 -input_format mjpeg \
  -video_size 1280x720 -framerate 30 -i /dev/video0 \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
  -f rtsp rtsp://localhost:8554/cam
```

MJPG is required for 720p30: raw video at that size needs more bandwidth than
USB 2.0 provides, so the camera drops to 10 fps.

## Health check

```bash
./check-stream.sh                         # checks rtsp://localhost:8554/cam
./check-stream.sh rtsp://HOST:8554/PATH   # any stream
```

| Situation | Output | Exit |
|---|---|---|
| Stream healthy | `UP` | 0 |
| Server up, nothing publishing on that path | `DOWN: no stream on the path` | 1 |
| Hostname doesn't resolve | `DOWN: bad hostname` | 1 |
| Nothing answers | `DOWN: no answer (timed out)` | 1 |
| Anything else | `DOWN: unknown error: ...` | 1 |

ffprobe returns exit code 1 for both a 404 and a bad hostname, so the script
reads the error text to tell them apart. A timeout leaves no text at all, only
exit code 124. An unmatched failure falls to `else` and reports DOWN, never a
silent pass.

## Troubleshooting log

- **UDP video blocked:** Docker's port mapping dropped the stream after about
  11 seconds. Fixed with host networking.
- **Server didn't return after reboot:** default restart policy is `no`.
  Fixed with `--restart always`.
- **Logs in UTC despite `TZ`:** the minimal image has no time zone files.
  Fixed by mounting the host's zoneinfo read-only.
- **Health check timed out on a healthy stream:** checks took 4 to 5 seconds
  against a 5-second timeout. First hypothesis (waiting on keyframes) predicted
  scattered times; measured times were bunched at 4.2 and 5.1 s, so it was
  rejected. Second hypothesis: ffprobe's default 5-second `analyzeduration`.
  With `-analyzeduration 1000000`, checks take 1.2 s, three runs in a row.

## Next

- systemd service so the camwatch stream starts at boot with no one logged in
- GPU object detection on the feed, offline, in a container
