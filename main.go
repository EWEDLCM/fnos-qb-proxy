package main

import (
    "bytes"
    "context"
    "flag"
    "fmt"
    "io"
    "log"
    "net"
    "net/http"
    "net/http/httputil"
    "net/url"
    "os"
    "os/exec"
    "regexp"
    "strings"
    "strconv"
    "time"
)

func fetchQbPassword() (string, error) {
    // exec command "ps aux | grep [q]bittorrent-nox"
    cmd := exec.Command("bash", "-c", "ps aux | grep [q]bittorrent-nox")
    output, err := cmd.Output()
    if err != nil {
        return "", fmt.Errorf("exec command %s: %w", cmd.String(), err)
    }

    // parse output(likes --webui-password=xxx) to get password
    re := regexp.MustCompile(`--webui-password=(\S+)`)
    matches := re.FindStringSubmatch(string(output))
    if len(matches) > 1 {
        return matches[1], nil
    }

    return "", fmt.Errorf("no qbittorrent-nox process found")
}

func watchQbPassword(ch chan string) {
    ticker := time.NewTicker(1 * time.Second)
    for range ticker.C {
        password, err := fetchQbPassword()
        if err != nil {
            fmt.Printf("fetch qbittorrent-nox password: %v\n", err)
            continue
        }

        ch <- password
    }
}

func main() {
    uds := flag.String("uds", "/home/admin/qbt.sock", "qBittorrent unix domain socket(uds) path")
    debug := flag.Bool("debug", false, "enable debug logging")
    port := flag.Int("port", 8080, "proxy running port")
    expectedPassword := flag.String("password", "", "if not set, any password will be accepted")

    flag.Parse()

    portStr := os.Getenv("FNOS_QB_PROXY_PORT")
    if portStr != "" {
        p, err := strconv.Atoi(portStr)
        if err != nil {
            log.Fatalf("invalid port number: %s", portStr)
        }
        *port = p
    }

    password, err := fetchQbPassword()
    if err != nil {
        log.Fatalf("fetch qbittorrent-nox password: %v", err)
    }

    debugf := func(format string, args ...interface{}) {
        if *debug {
            fmt.Printf(format, args...)
        }
    }

    fmt.Printf("proxy running on port %d\n", *port)

    ch := make(chan string)
    go watchQbPassword(ch)
    go func() {
        for newPassword := range ch {
            if newPassword == password {
                continue
            }

            password = newPassword
            fmt.Printf("new password: %s\n", password)
        }
    }()

    targetURL, _ := url.Parse(fmt.Sprintf("http://file://%s", *uds))
    proxy := httputil.NewSingleHostReverseProxy(targetURL)
    proxy.Transport = &http.Transport{
        DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
            return net.Dial("unix", *uds)
        },
    }

    proxy.Director = func(r *http.Request) {
        debugf("request: %v\n", r.URL.Path)
        r.URL.Scheme = "http"
        r.URL.Host = fmt.Sprintf("file://%s", *uds)
        r.Host = fmt.Sprintf("file://%s", *uds)

        body := []byte{}
        if r.Body != nil {
            body, _ = io.ReadAll(r.Body)
            r.Body = io.NopCloser(bytes.NewBuffer(body))
        }

        r.ParseForm()
        if strings.Contains(r.URL.Path, "/api/v2/auth/login") {
            outPassword := password
            if *expectedPassword != "" {
                parts := strings.Split(string(body), "&")
                debugf("parts: %v\n", parts)
                for _, part := range parts {
                    if strings.HasPrefix(part, "password=") {
                        inputPassword := strings.TrimPrefix(part, "password=")
                        if inputPassword != *expectedPassword {
                            outPassword = ""
                            break
                        }
                    }
                }
            }

            body = []byte(fmt.Sprintf("username=admin&password=%s", outPassword))
            r.Header.Set("Content-Length", fmt.Sprintf("%d", len(body)))
            r.ContentLength = int64(len(body))
            r.Body = io.NopCloser(bytes.NewBuffer(body))
        }
        r.Header.Del("Referer")
        r.Header.Del("Origin")
    }

    err = http.ListenAndServe(fmt.Sprintf(":%d", *port), proxy)
    if err != nil {
        log.Fatalf("listen and serve: %v", err)
    }
}
