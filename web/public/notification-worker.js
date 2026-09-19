self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      const client = clients.find((entry) => entry.url.startsWith(self.registration.scope));
      return client ? client.focus() : self.clients.openWindow(self.registration.scope);
    }),
  );
});
