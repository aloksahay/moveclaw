"use client";

import { Button } from "@/components/ui/button";
import { Header } from "@/components/header";
import { WalletDemoContent } from "@/components/wallet-demo-content";
import { WalletSelectionModal } from "@/components/wallet-selection-modal";
import { useWallet } from "@aptos-labs/wallet-adapter-react";

export default function Home() {
  const { 
    account, 
    connected
  } = useWallet();

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <Header />
      
      <main className={`flex-1 container mx-auto px-4 ${connected ? "py-8" : "flex items-center justify-center"}`}>
        {connected && account?.address ? (
          <WalletDemoContent />
        ) : (
          <div className="max-w-2xl mx-auto text-center space-y-8">
            <div className="space-y-4">
              <h1 className="text-4xl font-bold tracking-tight text-foreground sm:text-5xl">
                MoveClaw
              </h1>
              <p className="text-xl text-muted-foreground">
                Open Claw Hackathon — Store messages on-chain with Movement Network
              </p>
            </div>

            <WalletSelectionModal>
              <Button size="lg" className="text-lg px-8 py-6">
                Connect Wallet
              </Button>
            </WalletSelectionModal>
          </div>
        )}
      </main>

      <footer className="border-t border-border mt-auto">
        <div className="container mx-auto px-4 py-6 text-center text-sm text-muted-foreground">
          <p>MoveClaw • Open Claw Hackathon @ ETH Denver</p>
        </div>
      </footer>
    </div>
  );
}
