# Rheo
Email client like superhuman

## Gmail OAuth setup

Create a `.env` file in the `KeyboardMail` directory and add your Google OAuth
client ID:

```dotenv
GMAIL_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

The app loads `.env` from the current directory or its parent directories.
Environment variables take precedence over values in `.env`. Keep `.env` local;
it is ignored by Git. Then start the app from VS Code or run `swift run` from
`KeyboardMail`. Sign-in opens your system browser and uses Google's Desktop
OAuth loopback redirect with PKCE; create a **Desktop app** OAuth client in
Google Cloud Console.
