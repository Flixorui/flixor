import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Flixor - Your Plex Library, Reimagined",
  description: "A beautiful, native client for Plex. Stream your media with a Netflix-like experience on Web, macOS, iOS, and Android (with more platforms coming soon).",
  keywords: ["plex", "media", "streaming", "macos", "ios", "tvos", "netflix", "client"],
  openGraph: {
    title: "Flixor - Your Plex Library, Reimagined",
    description: "A beautiful, native client for Plex. Stream your media with a Netflix-like experience on Web, macOS, iOS, and Android (with more platforms coming soon).",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Flixor - Your Plex Library, Reimagined",
    description: "A beautiful, native client for Plex. Stream your media with a Netflix-like experience on Web, macOS, iOS, and Android (with more platforms coming soon).",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
