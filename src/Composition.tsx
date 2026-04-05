import { AbsoluteFill, useCurrentFrame } from "remotion";

export const MyComposition: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        backgroundColor: "white",
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <h1 style={{ fontSize: 80 }}>Frame {frame}</h1>
    </AbsoluteFill>
  );
};
