// Service icon components matching Mobile implementation exactly

type IconProps = {
  size?: number;
  className?: string;
  color?: string;
};

// Plex icon - matches mobile exactly
export function PlexIcon({ size = 24, color = '#e5e7eb' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512">
      <path
        d="m256 70h-108l108 186-108 186h108l108-186z"
        fill={color}
      />
    </svg>
  );
}

// TMDB icon - matches mobile exactly
export function TMDBIcon({ size = 24, color = '#e5e7eb' }: IconProps) {
  const width = size * (185.04 / 133.4);
  return (
    <svg width={width} height={size} viewBox="0 0 185.04 133.4">
      <path
        fill={color}
        d="M51.06,66.7h0A17.67,17.67,0,0,1,68.73,49h-.1A17.67,17.67,0,0,1,86.3,66.7h0A17.67,17.67,0,0,1,68.63,84.37h.1A17.67,17.67,0,0,1,51.06,66.7Zm82.67-31.33h32.9A17.67,17.67,0,0,0,184.3,17.7h0A17.67,17.67,0,0,0,166.63,0h-32.9A17.67,17.67,0,0,0,116.06,17.7h0A17.67,17.67,0,0,0,133.73,35.37Zm-113,98h63.9A17.67,17.67,0,0,0,102.3,115.7h0A17.67,17.67,0,0,0,84.63,98H20.73A17.67,17.67,0,0,0,3.06,115.7h0A17.67,17.67,0,0,0,20.73,133.37Zm83.92-49h6.25L125.5,49h-8.35l-8.9,23.2h-.1L99.4,49H90.5Zm32.45,0h7.8V49h-7.8Zm22.2,0h24.95V77.2H167.1V70h15.35V62.8H167.1V56.2h16.25V49h-24ZM10.1,35.4h7.8V6.9H28V0H0V6.9H10.1ZM39,35.4h7.8V20.1H61.9V35.4h7.8V0H61.9V13.2H46.75V0H39Zm41.25,0h25V28.2H88V21h15.35V13.8H88V7.2h16.25V0h-24Zm-79,49H9V57.25h.1l9,27.15H24l9.3-27.15h.1V84.4h7.8V49H29.45l-8.2,23.1h-.1L13,49H1.2Zm112.09,49H126a24.59,24.59,0,0,0,7.56-1.15,19.52,19.52,0,0,0,6.35-3.37,16.37,16.37,0,0,0,4.37-5.5A16.91,16.91,0,0,0,146,115.8a18.5,18.5,0,0,0-1.68-8.25,15.1,15.1,0,0,0-4.52-5.53A18.55,18.55,0,0,0,133.07,99,33.54,33.54,0,0,0,125,98H113.29Zm7.81-28.2h4.6a17.43,17.43,0,0,1,4.67.62,11.68,11.68,0,0,1,3.88,1.88,9,9,0,0,1,2.62,3.18,9.87,9.87,0,0,1,1,4.52,11.92,11.92,0,0,1-1,5.08,8.69,8.69,0,0,1-2.67,3.34,10.87,10.87,0,0,1-4,1.83,21.57,21.57,0,0,1-5,.55H121.1Zm36.14,28.2h14.5a23.11,23.11,0,0,0,4.73-.5,13.38,13.38,0,0,0,4.27-1.65,9.42,9.42,0,0,0,3.1-3,8.52,8.52,0,0,0,1.2-4.68,9.16,9.16,0,0,0-.55-3.2,7.79,7.79,0,0,0-1.57-2.62,8.38,8.38,0,0,0-2.45-1.85,10,10,0,0,0-3.18-1v-.1a9.28,9.28,0,0,0,4.43-2.82,7.42,7.42,0,0,0,1.67-5,8.34,8.34,0,0,0-1.15-4.65,7.88,7.88,0,0,0-3-2.73,12.9,12.9,0,0,0-4.17-1.3,34.42,34.42,0,0,0-4.63-.32h-13.2Zm7.8-28.8h5.3a10.79,10.79,0,0,1,1.85.17,5.77,5.77,0,0,1,1.7.58,3.33,3.33,0,0,1,1.23,1.13,3.22,3.22,0,0,1,.47,1.82,3.63,3.63,0,0,1-.42,1.8,3.34,3.34,0,0,1-1.13,1.2,4.78,4.78,0,0,1-1.57.65,8.16,8.16,0,0,1-1.78.2H165Zm0,14.15h5.9a15.12,15.12,0,0,1,2.05.15,7.83,7.83,0,0,1,2,.55,4,4,0,0,1,1.58,1.17,3.13,3.13,0,0,1,.62,2,3.71,3.71,0,0,1-.47,1.95,4,4,0,0,1-1.23,1.3,4.78,4.78,0,0,1-1.67.7,8.91,8.91,0,0,1-1.83.2h-7Z"
      />
    </svg>
  );
}

// Trakt icon - matches mobile exactly
export function TraktIcon({ size = 24, color = '#e5e7eb' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 144.8 144.8">
      <path
        d="m29.5 111.8c10.6 11.6 25.9 18.8 42.9 18.8 8.7 0 16.9-1.9 24.3-5.3l-40.4-40.3z"
        fill={color}
      />
      <path
        d="m56.1 60.6-30.6 30.5-4.1-4.1 32.2-32.2 37.6-37.6c-5.9-2-12.2-3.1-18.8-3.1-32.2 0-58.3 26.1-58.3 58.3 0 13.1 4.3 25.2 11.7 35l30.5-30.5 2.1 2 43.7 43.7c.9-.5 1.7-1 2.5-1.6l-48.3-48.3-29.3 29.3-4.1-4.1 33.4-33.4 2.1 2 51 50.9c.8-.6 1.5-1.3 2.2-1.9l-55-55z"
        fill={color}
      />
      <path
        d="m115.7 111.4c9.3-10.3 15-24 15-39 0-23.4-13.8-43.5-33.6-52.8l-36.7 36.6zm-41.2-44.6-4.1-4.1 28.9-28.9 4.1 4.1zm27.4-39.7-33.3 33.3-4.1-4.1 33.3-33.3z"
        fill={color}
      />
      <path
        d="m72.4 144.8c-39.9 0-72.4-32.5-72.4-72.4s32.5-72.4 72.4-72.4 72.4 32.5 72.4 72.4-32.5 72.4-72.4 72.4zm0-137.5c-35.9 0-65.1 29.2-65.1 65.1s29.2 65.1 65.1 65.1 65.1-29.2 65.1-65.1-29.2-65.1-65.1-65.1z"
        fill={color}
      />
    </svg>
  );
}

// MDBList icon - matches mobile exactly
export function MDBListIcon({ size = 24, color = '#e5e7eb' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 200 200">
      <path
        d="M0 0 C1.66792978 -0.00322218 3.33585625 -0.00904376 5.00376892 -0.01725769 C9.51621827 -0.03175056 14.02777213 -0.00890605 18.54011321 0.02160144 C23.26764201 0.04802245 27.99514496 0.04266913 32.72273254 0.04151917 C40.65742921 0.04432501 48.59178078 0.07032484 56.52636719 0.11132812 C65.69805194 0.15854934 74.86935941 0.17432053 84.04115695 0.17212147 C93.81318821 0.17009499 103.5850742 0.19091365 113.35706162 0.21846128 C116.17079296 0.22485272 118.98450083 0.22698443 121.79823875 0.22817802 C126.21837851 0.23119244 130.6382018 0.24951519 135.05823708 0.27967644 C136.67996915 0.28843466 138.30173764 0.29213092 139.92349243 0.29039383 C142.13745638 0.28891982 144.3505362 0.30590371 146.56437683 0.32762146 C147.80301578 0.33264899 149.04165472 0.33767653 150.31782818 0.34285641 C155.24261765 0.92801131 158.59115892 3.20576497 161.83262634 6.88911438 C166.27302108 13.16935275 165.37692865 20.80659707 165.29443359 28.16308594 C165.29765577 29.83101572 165.30347735 31.49894219 165.31169128 33.16685486 C165.32618415 37.67930421 165.30333964 42.19085806 165.27283216 46.70319915 C165.24641114 51.43072795 165.25176446 56.15823089 165.25291443 60.88581848 C165.25010859 68.82051515 165.22410875 76.75486672 165.18310547 84.68945312 C165.13588425 93.86113788 165.12011306 103.03244534 165.12231213 112.20424289 C165.1243386 121.97627415 165.10351995 131.74816014 165.07597232 141.52014756 C165.06958087 144.33387889 165.06744916 147.14758676 165.06625557 149.96132469 C165.06324115 154.38146445 165.0449184 158.80128774 165.01475716 163.22132301 C165.00599893 164.84305508 165.00230268 166.46482358 165.00403976 168.08657837 C165.00551377 170.30054231 164.98852989 172.51362214 164.96681213 174.72746277 C164.9617846 175.96610171 164.95675707 177.20474066 164.95157719 178.48091412 C164.36642229 183.40570359 162.08866863 186.75424486 158.40531921 189.99571228 C152.12508085 194.43610701 144.48783652 193.54001459 137.13134766 193.45751953 C135.46341787 193.46074171 133.7954914 193.46656329 132.12757874 193.47477722 C127.61512939 193.48927009 123.10357553 193.46642558 118.59123445 193.43591809 C113.86370564 193.40949708 109.1362027 193.4148504 104.40861511 193.41600037 C96.47391844 193.41319452 88.53956688 193.38719469 80.60498047 193.34619141 C71.43329571 193.29897019 62.26198825 193.283199 53.09019071 193.28539807 C43.31815945 193.28742454 33.54627346 193.26660588 23.77428603 193.23905826 C20.9605547 193.23266681 18.14684683 193.2305351 15.3331089 193.22934151 C10.91296915 193.22632709 6.49314586 193.20800434 2.07311058 193.17784309 C0.45137851 193.16908487 -1.17038999 193.16538861 -2.79214478 193.1671257 C-5.00610872 193.16859971 -7.21918854 193.15161582 -9.43302917 193.12989807 C-10.67166812 193.12487054 -11.91030706 193.11984301 -13.18648052 193.11466312 C-18.11127 192.52950822 -21.45981126 190.25175456 -24.70127869 186.56840515 C-29.14167342 180.28816678 -28.24558099 172.65092246 -28.16308594 165.29443359 C-28.16630812 163.62650381 -28.17212969 161.95857734 -28.18034363 160.29066467 C-28.1948365 155.77821532 -28.17199199 151.26666147 -28.1414845 146.75432038 C-28.11506349 142.02679158 -28.12041681 137.29928864 -28.12156677 132.57170105 C-28.11876093 124.63700438 -28.0927611 116.70265282 -28.05175781 108.76806641 C-28.00453659 99.59638165 -27.9887654 90.42507419 -27.99096447 81.25327665 C-27.99299095 71.48124539 -27.97217229 61.70935939 -27.94462466 51.93737197 C-27.93823322 49.12364064 -27.9361015 46.30993277 -27.93490791 43.49619484 C-27.9318935 39.07605508 -27.91357074 34.65623179 -27.8834095 30.23619652 C-27.87465127 28.61446445 -27.87095502 26.99269595 -27.87269211 25.37094116 C-27.87416611 23.15697722 -27.85718223 20.94389739 -27.83546448 18.73005676 C-27.82792318 16.87209835 -27.82792318 16.87209835 -27.82022953 14.97660542 C-27.23507463 10.05181594 -24.95732097 6.70327467 -21.27397156 3.46180725 C-14.99373319 -0.97858748 -7.35648886 -0.08249505 0 0 Z"
        fill={color}
        transform="translate(31.434326171875,3.271240234375)"
      />
      <path
        d="M0 0 C6.6 0 13.2 0 20 0 C20 31.35 20 62.7 20 95 C13.07 95 6.14 95 -1 95 C-1.495 61.835 -1.495 61.835 -2 28 C-4.31 30.31 -6.62 32.62 -9 35 C-10.27529263 36.14352808 -11.56342383 37.27327602 -12.875 38.375 C-16.6813875 41.64392853 -20.16510113 45.16156149 -23.62890625 48.7890625 C-26.5115847 51.47702956 -29.79271291 53.70908065 -33 56 C-33 47.75 -33 39.5 -33 31 C-32.01 30.67 -31.02 30.34 -30 30 C-30 29.34 -30 28.68 -30 28 C-28.53125 26.5546875 -28.53125 26.5546875 -26.5 24.875 C-23.53322639 22.35742098 -20.72425751 19.77831024 -18 17 C-14.81903568 13.7691382 -11.51632264 10.76272773 -8.0546875 7.8359375 C-5.26148833 5.34011315 -2.64868843 2.64868843 0 0 Z"
        fill="#0b0b0d"
        transform="translate(137,53)"
      />
      <path
        d="M0 0 C20 0 20 0 25.25 4.0625 C26.52181342 5.69153591 27.77330211 7.33672622 29 9 C30.25775906 10.16278542 31.5496412 11.28989548 32.875 12.375 C37.29289637 16.15544439 41.32611611 20.29459348 45.38671875 24.44921875 C47.84792716 27.08141814 47.84792716 27.08141814 50.8125 28.53515625 C54.61867348 32.82389815 53.51112253 38.25579538 53.3125 43.75 C53.28994141 44.92433594 53.26738281 46.09867188 53.24414062 47.30859375 C53.1852296 50.20701637 53.10301631 53.10286427 53 56 C45.07251219 49.23433606 37.23028913 42.42428166 29.984375 34.921875 C27.45416984 32.47136135 24.70594485 30.25495404 22 28 C21.67 50.11 21.34 72.22 21 95 C14.07 95 7.14 95 0 95 C0 63.65 0 32.3 0 0 Z"
        fill="#0b0b0d"
        transform="translate(43,53)"
      />
    </svg>
  );
}

// Overseerr icon - matches mobile exactly
export function OverseerrIcon({ size = 24, color }: IconProps) {
  if (color) {
    return (
      <svg width={size} height={size} viewBox="0 0 96 96" fill="none">
        <path
          fillRule="evenodd"
          clipRule="evenodd"
          d="M48 96C74.5097 96 96 74.5097 96 48C96 21.4903 74.5097 0 48 0C21.4903 0 0 21.4903 0 48C0 74.5097 21.4903 96 48 96ZM80.0001 52C80.0001 67.464 67.4641 80 52.0001 80C36.5361 80 24.0001 67.464 24.0001 52C24.0001 49.1303 24.4318 46.3615 25.2338 43.7548C27.4288 48.6165 32.3194 52 38.0001 52C45.7321 52 52.0001 45.732 52.0001 38C52.0001 32.3192 48.6166 27.4287 43.755 25.2337C46.3616 24.4317 49.1304 24 52.0001 24C67.4641 24 80.0001 36.536 80.0001 52Z"
          fill={color}
        />
      </svg>
    );
  }
  return (
    <svg width={size} height={size} viewBox="0 0 96 96" fill="none">
      <defs>
        <linearGradient id="overseerr_gradient" x1="48" y1="0" x2="117.5" y2="69.5" gradientUnits="userSpaceOnUse">
          <stop stopColor="#C395FC" />
          <stop offset="1" stopColor="#4F65F5" />
        </linearGradient>
      </defs>
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M48 96C74.5097 96 96 74.5097 96 48C96 21.4903 74.5097 0 48 0C21.4903 0 0 21.4903 0 48C0 74.5097 21.4903 96 48 96ZM80.0001 52C80.0001 67.464 67.4641 80 52.0001 80C36.5361 80 24.0001 67.464 24.0001 52C24.0001 49.1303 24.4318 46.3615 25.2338 43.7548C27.4288 48.6165 32.3194 52 38.0001 52C45.7321 52 52.0001 45.732 52.0001 38C52.0001 32.3192 48.6166 27.4287 43.755 25.2337C46.3616 24.4317 49.1304 24 52.0001 24C67.4641 24 80.0001 36.536 80.0001 52Z"
        fill="url(#overseerr_gradient)"
      />
    </svg>
  );
}

// Ionicons-style icons matching mobile (outline style)
export function PersonCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M258.9 48C141.92 46.42 46.42 141.92 48 258.9c1.56 112.19 92.91 203.54 205.1 205.1 117 1.6 212.48-93.9 210.88-210.88C462.44 140.91 371.09 49.56 258.9 48zm126.42 327.25a4 4 0 01-6.14-.32 124.27 124.27 0 00-32.35-29.59C321.37 329 289.11 320 256 320s-65.37 9-90.83 25.34a124.24 124.24 0 00-32.35 29.58 4 4 0 01-6.14.32A175.32 175.32 0 0180 259c-1.63-97.31 78.22-178.76 175.57-179S432 158.81 432 256a175.32 175.32 0 01-46.68 119.25z"/>
      <path d="M256 144c-19.72 0-37.55 7.39-50.22 20.82s-19 32-17.57 51.93C191.11 256 221.52 288 256 288s64.83-32 67.79-71.24c1.48-19.74-4.8-38.14-17.68-51.82C293.39 151.44 275.59 144 256 144z"/>
    </svg>
  );
}

export function CompassIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M448 256c0-106-86-192-192-192S64 150 64 256s86 192 192 192 192-86 192-192z"/>
      <path d="M350.67 150.93l-117.2 46.88a64 64 0 00-35.66 35.66l-46.88 117.2a8 8 0 0010.4 10.4l117.2-46.88a64 64 0 0035.66-35.66l46.88-117.2a8 8 0 00-10.4-10.4zM256 280a24 24 0 1124-24 24 24 0 01-24 24z"/>
    </svg>
  );
}

export function ColorPaletteIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M430.11 347.9c-6.6-6.1-16.3-7.6-24.6-9-11.5-1.9-15.9-4-22.6-10-14.3-12.7-14.3-31.1 0-43.8l30.3-26.9c46.4-41 46.4-108.2 0-149.2-34.2-30.1-80.1-45-127.8-45-55.7 0-113.9 20.3-158.8 60.1-83.5 73.8-83.5 194.7 0 268.5 41.5 36.7 97.5 55 152.9 55.4h1.7c55.4 0 110-17.9 148.8-52.4 14.4-12.7 11.99-36.6.1-47.7z"/>
      <circle cx="144" cy="208" r="32"/>
      <circle cx="152" cy="311" r="32"/>
      <circle cx="224" cy="144" r="32"/>
      <circle cx="256" cy="367" r="32"/>
      <circle cx="328" cy="144" r="32"/>
    </svg>
  );
}

export function LayersIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M434.8 137.65l-149.36-68.1c-16.19-7.4-42.69-7.4-58.88 0L77.3 137.65c-17.6 8-17.6 21.09 0 29.09l148 67.5c16.89 7.7 44.69 7.7 61.58 0l148-67.5c17.52-8 17.52-21.1-.08-29.09zM160 308.52l-82.7 37.11c-17.6 8-17.6 21.1 0 29.1l148 67.5c16.89 7.69 44.69 7.69 61.58 0l148-67.5c17.6-8 17.6-21.1 0-29.1l-82.78-37.11"/>
      <path d="M160 204.48l-82.8 37.16c-17.6 8-17.6 21.1 0 29.09l148 67.5c16.89 7.7 44.69 7.7 61.58 0l148-67.5c17.6-8 17.6-21.1 0-29.09l-82.78-37.16"/>
    </svg>
  );
}

export function PlayCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M448 256c0-106-86-192-192-192S64 150 64 256s86 192 192 192 192-86 192-192z"/>
      <path d="M216.32 334.44l114.45-69.14a10.89 10.89 0 000-18.6l-114.45-69.14a10.78 10.78 0 00-16.32 9.31v138.26a10.78 10.78 0 0016.32 9.31z"/>
    </svg>
  );
}

export function InformationCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M248 64C146.39 64 64 146.39 64 248s82.39 184 184 184 184-82.39 184-184S349.61 64 248 64z"/>
      <path d="M220 220h32v116"/>
      <path d="M208 340h88"/>
      <path d="M248 130a26 26 0 1026 26 26 26 0 00-26-26z"/>
    </svg>
  );
}

export function AlbumsIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="64" y="176" width="384" height="256" rx="28.87" ry="28.87"/>
      <path d="M144 80h224M112 128h288"/>
    </svg>
  );
}

export function HomeIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M80 212v236a16 16 0 0016 16h96V328a24 24 0 0124-24h80a24 24 0 0124 24v136h96a16 16 0 0016-16V212"/>
      <path d="M480 256L266.89 52c-5-5.28-16.69-5.34-21.78 0L32 256M400 179V64h-48v69"/>
    </svg>
  );
}

export function PlayIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M112 111v290c0 17.44 17 28.52 31 20.16l247.9-148.37c12.12-7.25 12.12-26.33 0-33.58L143 90.84c-14-8.36-31 2.72-31 20.16z"/>
    </svg>
  );
}

export function GridIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="48" y="48" width="176" height="176" rx="20" ry="20"/>
      <rect x="288" y="48" width="176" height="176" rx="20" ry="20"/>
      <rect x="48" y="288" width="176" height="176" rx="20" ry="20"/>
      <rect x="288" y="288" width="176" height="176" rx="20" ry="20"/>
    </svg>
  );
}

export function ImageIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="48" y="80" width="416" height="352" rx="48" ry="48"/>
      <circle cx="336" cy="176" r="32"/>
      <path d="M304 335.79l-90.66-90.49a32 32 0 00-43.87-1.3L48 352M224 432l123.34-123.34a32 32 0 0143.11-2L464 368"/>
    </svg>
  );
}

export function StarIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M480 208H308L256 48l-52 160H32l140 96-54 160 138-100 138 100-54-160z"/>
    </svg>
  );
}

export function StatsChartIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="64" y="320" width="48" height="160" rx="8" ry="8"/>
      <rect x="288" y="224" width="48" height="256" rx="8" ry="8"/>
      <rect x="400" y="112" width="48" height="368" rx="8" ry="8"/>
      <rect x="176" y="32" width="48" height="448" rx="8" ry="8"/>
    </svg>
  );
}

export function FlameIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M112 320c0-93 124-165 96-272 66 0 192 96 192 272a144 144 0 01-288 0z"/>
      <path d="M320 368c0 57.71-32 80-64 80s-64-22.29-64-80 40-86 40-86c0 71 48 54 48 54-24 0 40 6 40 32z"/>
    </svg>
  );
}

export function LeafIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M321.89 171.42C233 114 141 155.22 56 65.22c-19.8-21-8.3 235.5 98.1 332.7 77.79 71 197.9 63.08 238.4-5.92s18.28-163.17-70.61-220.58zM173 253c86 81 175 129 292 147"/>
    </svg>
  );
}

export function PeopleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M402 168c-2.93 40.67-33.1 72-66 72s-63.12-31.32-66-72c-3-42.31 26.37-72 66-72s69 30.46 66 72z"/>
      <path d="M336 304c-65.17 0-127.84 32.37-143.54 95.41-2.08 8.34 3.15 16.59 11.72 16.59h263.65c8.57 0 13.77-8.25 11.72-16.59C463.85 335.36 401.18 304 336 304z"/>
      <path d="M200 185.94c-2.34 32.48-26.72 58.06-53 58.06s-50.7-25.57-53-58.06C91.61 152.15 115.34 128 147 128s55.39 24.77 53 57.94z"/>
      <path d="M206 306c-18.05-8.27-37.93-11.45-59-11.45-52 0-102.1 25.85-114.65 76.2-1.65 6.66 2.53 13.25 9.37 13.25H154"/>
    </svg>
  );
}

export function ShieldIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M463.1 112.37C373.68 96.33 336.71 84.45 256 48c-80.71 36.45-117.68 48.33-207.1 64.37C32.7 369.13 240.58 457.79 256 464c15.42-6.21 223.3-94.87 207.1-351.63z"/>
    </svg>
  );
}

export function BugIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M370 378c28.89 23.52 46 46.07 46 86M142 378c-28.89 23.52-46 46.06-46 86M384 208c28.89-23.52 32-56.07 32-96M128 208c-28.89-23.52-32-56.07-32-96M464 288c0 0-0 .17-.12.43 0-2.15.12-7.43.12-8.43 0-88.22-55.6-160-144-160h-128c-88.4 0-144 71.78-144 160 0 1 .12 6.28.12 8.43-.08-.26-.12-.43-.12-.43"/>
      <path d="M256 320a64 64 0 0164-64"/>
      <ellipse cx="256" cy="320" rx="160" ry="144"/>
      <path d="M192 272a16 16 0 1016-16 16 16 0 00-16 16zM336 272a16 16 0 10-16-16 16 16 0 0016 16z"/>
    </svg>
  );
}

export function CloudDownloadIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M320 336h76c55 0 100-21.21 100-75.6s-53-73.47-96-75.6C391.11 99.74 329 48 256 48c-69 0-113.44 45.79-128 91.2-60 5.7-112 35.88-112 98.4S70 336 136 336h56M192 400.1l64 63.9 64-63.9M256 224v224.03"/>
    </svg>
  );
}

export function ChatbubblesIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M431 320.6c-1-3.6 1.2-8.6 3.3-12.2a33.68 33.68 0 012.1-3.1A162 162 0 00464 215c.3-92.2-77.5-167-173.7-167-83.9 0-153.9 57.1-170.3 132.9a160.7 160.7 0 00-3.7 34.2c0 92.3 74.8 169.1 171 169.1 15.3 0 35.9-4.6 47.2-7.7s22.5-7.2 25.4-8.3a26.44 26.44 0 019.3-1.7 26 26 0 0110.1 2l56.7 20.1a13.52 13.52 0 003.9 1 8 8 0 008-8 12.85 12.85 0 00-.5-2.7z"/>
      <path d="M66.46 232a146.23 146.23 0 006.39 152.67c2.31 3.49 3.61 6.19 3.21 8s-11.93 61.87-11.93 61.87a8 8 0 002.71 7.68A8.17 8.17 0 0072 464a7.26 7.26 0 002.91-.6l56.21-22a15.7 15.7 0 0112 .2c18.94 7.38 39.88 12 60.83 12A159.21 159.21 0 00284 432.11"/>
    </svg>
  );
}

export function ChatboxEllipsesIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M408 64H104a56.16 56.16 0 00-56 56v192a56.16 56.16 0 0056 56h40v80l93.72-78.14a8 8 0 015.13-1.86H408a56.16 56.16 0 0056-56V120a56.16 56.16 0 00-56-56z"/>
      <circle cx="160" cy="216" r="32"/>
      <circle cx="256" cy="216" r="32"/>
      <circle cx="352" cy="216" r="32"/>
    </svg>
  );
}

export function FlashIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M315.27 33L96 304h128l-31.51 173.23a2.36 2.36 0 002.33 2.77 2.36 2.36 0 001.89-.95L416 208H288l31.66-173.25a2.45 2.45 0 00-2.44-2.75 2.42 2.42 0 00-1.95 1z"/>
    </svg>
  );
}

export function RefreshIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M320 146s24.36-12-64-12a160 160 0 10160 160"/>
      <path d="M256 58l80 80-80 80"/>
    </svg>
  );
}

export function LibraryIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="32" y="96" width="64" height="368" rx="16" ry="16"/>
      <line x1="112" y1="224" x2="240" y2="224"/>
      <line x1="112" y1="400" x2="240" y2="400"/>
      <rect x="112" y="160" width="128" height="304" rx="16" ry="16"/>
      <rect x="256" y="48" width="96" height="416" rx="16" ry="16"/>
      <path d="M422.46 96.11l-40.4 4.25c-11.12 1.17-19.18 11.57-17.93 23.1l34.92 321.59c1.26 11.53 11.37 20 22.49 18.84l40.4-4.25c11.12-1.17 19.18-11.57 17.93-23.1L445 115c-1.31-11.58-11.42-20.06-22.54-18.89z"/>
    </svg>
  );
}

export function ChevronForwardIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="48" strokeLinecap="round" strokeLinejoin="round">
      <path d="M184 112l144 144-144 144"/>
    </svg>
  );
}

export function ChevronBackIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="48" strokeLinecap="round" strokeLinejoin="round">
      <path d="M328 112L184 256l144 144"/>
    </svg>
  );
}

export function CheckmarkCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M448 256c0-106-86-192-192-192S64 150 64 256s86 192 192 192 192-86 192-192z"/>
      <path d="M352 176L217.6 336 160 272"/>
    </svg>
  );
}

export function AlertCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M448 256c0-106-86-192-192-192S64 150 64 256s86 192 192 192 192-86 192-192z"/>
      <path d="M250.26 166.05L256 288l5.73-121.95a5.74 5.74 0 00-5.79-6h0a5.74 5.74 0 00-5.68 6z"/>
      <path d="M256 367.91a20 20 0 1120-20 20 20 0 01-20 20z"/>
    </svg>
  );
}

export function AnalyticsIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M456 128a40 40 0 00-37.23 54.6l-84.17 84.17a39.86 39.86 0 00-29.2 0l-60.17-60.17a40 40 0 10-74.46 0L70.6 306.77a40 40 0 1022.63 22.63L193.4 229.23a39.86 39.86 0 0029.2 0l60.17 60.17a40 40 0 1074.46 0l84.17-84.17A40 40 0 10456 128z"/>
    </svg>
  );
}

export function OpenOutlineIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M384 224v184a40 40 0 01-40 40H104a40 40 0 01-40-40V168a40 40 0 0140-40h167.48"/>
      <path d="M336 64h112v112"/>
      <path d="M224 288L440 72"/>
    </svg>
  );
}

export function ServerIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="256" cy="128" rx="192" ry="80"/>
      <path d="M448 214c0 44.18-86 80-192 80S64 258.18 64 214"/>
      <path d="M448 128v172c0 44.18-86 80-192 80S64 344.18 64 300V128"/>
      <path d="M448 300v84c0 44.18-86 80-192 80S64 428.18 64 384v-84"/>
    </svg>
  );
}

export function KeyIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M218.1 167.17c0 13 0 25.6 4.1 37.4-43.1 50.6-156.9 184.3-167.5 194.5a20.17 20.17 0 00-6.7 15c0 8.5 5.2 16.7 9.6 21.3 6.6 6.9 34.8 33 40 28 15.4-15 18.5-19 24.8-25.2 9.5-9.3-1-28.3 2.3-36s6.8-9.2 12.5-10.4 15.8 2.9 23.7 3c8.3.1 12.8-3.4 19-9.2 5-4.6 8.6-8.9 8.7-15.6.2-9-12.8-20.9-3.1-30.4s23.7 6.2 34 5 22.8-15.5 24.1-21.6-11.7-21.8-9.7-30.7c.7-3 6.8-10 11.4-11s14 5.5 21.3 2.2 10.3-9.4 10.3-9.4"/>
      <circle cx="400" cy="144" r="48"/>
      <path d="M304 288s76-56 136-72"/>
    </svg>
  );
}

export function FilmIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="48" y="96" width="416" height="320" rx="28" ry="28"/>
      <rect x="384" y="336" width="80" height="80" rx="28" ry="28"/>
      <rect x="384" y="256" width="80" height="80" rx="28" ry="28"/>
      <rect x="384" y="176" width="80" height="80" rx="28" ry="28"/>
      <rect x="384" y="96" width="80" height="80" rx="28" ry="28"/>
      <rect x="48" y="336" width="80" height="80" rx="28" ry="28"/>
      <rect x="48" y="256" width="80" height="80" rx="28" ry="28"/>
      <rect x="48" y="176" width="80" height="80" rx="28" ry="28"/>
      <rect x="48" y="96" width="80" height="80" rx="28" ry="28"/>
    </svg>
  );
}

export function TvIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="32" y="96" width="448" height="272" rx="32.14" ry="32.14"/>
      <path d="M128 416h256"/>
    </svg>
  );
}

export function LanguageIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M48 112h288M192 64v48M272 448l96-224 96 224M301.5 384h133M281.3 112S257 206 199 277 80 384 80 384"/>
      <path d="M256 336s-35-27-72-75-56-85-56-85"/>
    </svg>
  );
}

export function CloseCircleIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M448 256c0-106-86-192-192-192S64 150 64 256s86 192 192 192 192-86 192-192z"/>
      <path d="M320 320L192 192M192 320l128-128"/>
    </svg>
  );
}

export function CopyIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <rect x="128" y="128" width="336" height="336" rx="57" ry="57"/>
      <path d="M383.5 128l.5-24a56.16 56.16 0 00-56-56H112a64.19 64.19 0 00-64 64v216a56.16 56.16 0 0056 56h24"/>
    </svg>
  );
}

export function CheckmarkIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M416 128L192 384l-96-96"/>
    </svg>
  );
}

export function CloudIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="32" strokeLinecap="round" strokeLinejoin="round">
      <path d="M400 240c-8.89-89.54-71-160-160-160-64.08 0-119.54 37.72-145 92.33A96 96 0 0096 368h304a96 96 0 000-128z"/>
    </svg>
  );
}

export function ChevronDownIcon({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" stroke={color} strokeWidth="48" strokeLinecap="round" strokeLinejoin="round">
      <path d="M112 184l144 144 144-144"/>
    </svg>
  );
}

// Wrapper and service icon exports
export function SettingsIconWrapper({
  children,
  bgColor = 'bg-gray-600',
  size = 28,
  className = '',
}: {
  children: React.ReactNode;
  bgColor?: string;
  size?: number;
  className?: string;
}) {
  return (
    <div
      className={`flex items-center justify-center rounded-lg ${bgColor} ${className}`}
      style={{ width: size, height: size }}
    >
      {children}
    </div>
  );
}

// Legacy exports for backward compatibility
export { PlexIcon as PlexServiceIcon };
export { TMDBIcon as TMDBServiceIcon };
export { TraktIcon as TraktServiceIcon };
export { MDBListIcon as MDBListServiceIcon };
export { OverseerrIcon as OverseerrServiceIcon };

// Alias for backward compatibility
export const DetailsIcon = InformationCircleIcon;
export const AppearanceIcon = ColorPaletteIcon;
export const IntegrationsIcon = LayersIcon;
export const AboutIcon = InformationCircleIcon;
export const CatalogIcon = AlbumsIcon;
export const RowsIcon = GridIcon;
export const ExternalLinkIcon = ChevronForwardIcon;
