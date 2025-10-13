type MediaInfo = {
  rating?: string;
  runtimeMin?: number;
  videoCodec?: string;
  videoProfile?: string;
  resolution?: string;
  bitrateKbps?: number;
  audioCodec?: string;
  audioChannels?: number;
  fileSizeMB?: number;
  subsCount?: number;
};

export default function TechnicalChips({ info }: { info: MediaInfo }) {
  const chips: string[] = [];
  if (info.rating) chips.push(info.rating);
  if (info.runtimeMin) chips.push(`${info.runtimeMin} min`);
  if (info.resolution) chips.push(info.resolution);
  if (info.videoCodec) chips.push(info.videoCodec.toUpperCase());
  if (info.audioCodec) chips.push(`${info.audioCodec.toUpperCase()} ${info.audioChannels || ''}`.trim());
  if (info.bitrateKbps) chips.push(`${Math.round(info.bitrateKbps/1000)} Mbps`);
  if (info.fileSizeMB) chips.push(`${Math.round(info.fileSizeMB)} MB`);
  if (info.subsCount) chips.push(`${info.subsCount} subs`);
  return (
    <div className="flex flex-wrap gap-2 mt-2">
      {chips.map((c, i) => <span key={i} className="chip">{c}</span>)}
    </div>
  );
}

