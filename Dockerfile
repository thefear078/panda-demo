FROM nginx:1.27-alpine

RUN rm -rf /usr/share/nginx/html/* \
    && mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp \
    && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /tmp \
    && touch /tmp/nginx.pid \
    && chown nginx:nginx /tmp/nginx.pid

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY app/ /usr/share/nginx/html/

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=20s --timeout=3s --start-period=8s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
