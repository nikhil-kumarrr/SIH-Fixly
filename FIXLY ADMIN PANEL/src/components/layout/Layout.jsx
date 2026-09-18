import React, { useState } from 'react';
import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import Header from './Header';

export default function Layout() {
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  return (
    <div style={{ display: 'flex', minHeight: '100vh', width: '100%', maxWidth: '100vw', overflowX: 'hidden', backgroundColor: 'var(--bg-app)' }}>
      {/* Sidebar */}
      <Sidebar isOpen={isSidebarOpen} setIsOpen={setIsSidebarOpen} />

      {/* Main Workspace Area */}
      <div
        className="main-workspace"
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          minWidth: 0,
          width: '100%',
          maxWidth: '100vw',
          height: '100vh',
          overflowY: 'auto',
          overflowX: 'hidden',
          boxInverted: 'border-box',
        }}
      >
        <Header onOpenMobileMenu={() => setIsSidebarOpen(true)} />
        
        <main style={{ flex: 1, width: '100%', maxWidth: '100%', overflowX: 'hidden', boxSizing: 'border-box', paddingBottom: '32px' }}>
          <Outlet />
        </main>
      </div>
    </div>
  );
}
