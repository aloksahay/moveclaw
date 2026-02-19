"use client";

import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";
import { toast } from "sonner";
import { MOVECLAW_MESSAGE } from "@/lib/contracts";

const MOVEMENT_TESTNET = {
  fullnode: "https://full.testnet.movementinfra.xyz/v1",
  explorer: "testnet",
};

export function MessageContract() {
  const { account, signAndSubmitTransaction } = useWallet();
  const [message, setMessage] = useState("");
  const [storedMessage, setStoredMessage] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isFetching, setIsFetching] = useState(false);

  const getAptosClient = () => {
    const config = new AptosConfig({
      network: Network.CUSTOM,
      fullnode: MOVEMENT_TESTNET.fullnode,
    });
    return new Aptos(config);
  };

  const fetchMessage = async () => {
    if (!account?.address) return;

    setIsFetching(true);
    try {
      const aptos = getAptosClient();
      const viewResult = await aptos.view({
        payload: {
          function: MOVECLAW_MESSAGE.getMessage,
          functionArguments: [account.address.toString()],
        },
      });
      setStoredMessage(viewResult[0] as string);
    } catch (err: unknown) {
      const error = err as { message?: string };
      if (error?.message?.includes("TABLE_ITEM_NOT_FOUND") || error?.message?.includes("not_found")) {
        setStoredMessage(null);
      } else {
        toast.error("Failed to fetch message");
        setStoredMessage(null);
      }
    } finally {
      setIsFetching(false);
    }
  };

  useEffect(() => {
    if (account?.address) {
      fetchMessage();
    } else {
      setStoredMessage(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account?.address]);

  const handleSetMessage = async () => {
    if (!account) {
      toast.error("Connect your wallet first");
      return;
    }

    if (!message.trim()) {
      toast.error("Please enter a message");
      return;
    }

    setIsLoading(true);
    const loadingToast = toast.loading("Setting message on-chain...");

    try {
      const response = await signAndSubmitTransaction({
        sender: account.address,
        data: {
          function: MOVECLAW_MESSAGE.setMessage,
          functionArguments: [message.trim()],
        },
      });

      toast.loading("Waiting for confirmation...", { id: loadingToast });

      const aptos = getAptosClient();
      await aptos.waitForTransaction({ transactionHash: response.hash });

      toast.success("Message saved on-chain!", {
        id: loadingToast,
        action: {
          label: "View tx",
          onClick: () =>
            window.open(
              `https://explorer.movementnetwork.xyz/txn/${response.hash}?network=${MOVEMENT_TESTNET.explorer}`,
              "_blank"
            ),
        },
      });

      setMessage("");
      await fetchMessage();
    } catch (err: unknown) {
      const error = err as { message?: string };
      toast.error(error?.message || "Failed to set message", { id: loadingToast });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>MoveClaw Message</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Store a message on Movement Network. Your message lives on-chain forever!
        </p>

        {storedMessage !== null && (
          <div className="rounded-lg border bg-muted/50 p-3">
            <p className="text-xs font-medium text-muted-foreground mb-1">Your stored message</p>
            <p className="text-sm font-mono break-words">{storedMessage || "(empty)"}</p>
          </div>
        )}

        <div className="space-y-2">
          <label className="text-sm font-medium">New message</label>
          <Input
            placeholder="Hello, Open Claw!"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            disabled={isLoading}
          />
        </div>

        <div className="flex gap-2">
          <Button
            onClick={handleSetMessage}
            disabled={isLoading || !account}
            className="flex-1"
          >
            {isLoading ? "Setting..." : "Set Message"}
          </Button>
          <Button variant="outline" onClick={fetchMessage} disabled={isFetching || !account}>
            {isFetching ? "..." : "Refresh"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
