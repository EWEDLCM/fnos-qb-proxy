package main

import (
    "bytes"
    "context"
    "fmt"
    "io"
    "log"
    "net"
    "net/http"
    "net/http/httputil"
    "net/url" // 导入 net/url 包
    "os"
    "os/exec"
    "regexp"
    "strings"
    "strconv" // 导入 strconv 包
    "time"

    "github.com/urfave/cli/v2"
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

func proxyCmd(ctx *cli.Context) error {
    uds := ctx.String("uds")
    debug := ctx.Bool("debug")
    portStr := os.Getenv("FNOS_QB_PROXY_PORT")
    var port int
    if portStr != "" {
        port, _ = strconv.Atoi(portStr)
    } else {
        port = ctx.Int("port")
    }
    expectedPassword := ctx.String("password")
    password, err := fetchQbPassword()
    if err != nil {
        return fmt.Errorf("fetch qbittorrent-nox password: %w", err)
    }

    debugf := func(format string, args ...any) {
        if debug {
            fmt.Printf(format, args...)
        }
    }

    fmt.Printf("proxy running on port %d\n", port)

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

    targetURL, _ := url.Parse(fmt.Sprintf("http://file://%s", uds))
    proxy := httputil.NewSingleHostReverseProxy(targetURL)
    proxy.Transport = &http.Transport{
        DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
            return net.Dial("unix", uds)
        },
    }

    proxy.Director = func(r *http.Request) {
        debugf("request: %v\n", r.URL.Path)
        r.URL.Scheme = "http"
        r.URL.Host = fmt.Sprintf("file://%s", uds)
        r.Host = fmt.Sprintf("file://%s", uds)

        body, _ := io.ReadAll(r.Body)
        r.ParseForm()
        if strings.Contains(r.URL.Path, "/api/v2/auth/login") {
            outPassword := password
            if expectedPassword != "" {
                parts := strings.Split(string(body), "&")
                debugf("parts: %v\n", parts)
                for _, part := range parts {
                    if strings.HasPrefix(part, "password=") {
                        inputPassword := strings.TrimPrefix(part, "password=")
                        if inputPassword != expectedPassword {
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

    err = http.ListenAndServe(fmt.Sprintf(":%d", port), proxy)
    if err != nil {
        return fmt.Errorf("listen and serve: %w", err)
    }
    return nil
}

func main() {
    app := &cli.App{
        Name:   "fnos-qb-proxy",
        Usage:  "fnos-qb-proxy is a proxy for qBittorrent in fnOS",
        Action: proxyCmd,
        Flags: []cli.Flag{
            &cli.StringFlag{
                Name:    "password",
                Aliases: []string{"p"},
                Usage:   "if not set, any password will be accepted",
                Value:   "",
            },
            &cli.StringFlag{
                Name:  "uds",
                Usage: "qBittorrent unix domain socket(uds) path",
                Value: "/home/admin/qbt.sock",
            },
            &cli.BoolFlag{
                Name:    "debug",
                Aliases: []string{"d"},
                Value:   false,
            },
            &cli.IntFlag{
                Name:  "port",
                Usage: "proxy running port",
                Value: 8080,
            },
        },
    }

    err := app.Run(os.Args)
    if err != nil {
        log.Fatal(err)
    }
}
