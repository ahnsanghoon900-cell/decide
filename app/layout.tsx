import './globals.css';
import type { Metadata } from 'next';
export const metadata: Metadata = { title: 'DECIDE — 선택을 도와주는 사람들', description: '두세 가지 선택지 중 무엇이 더 나은지 사람들에게 물어보세요.' };
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="ko"><body>{children}</body></html>; }
