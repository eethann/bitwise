// This is an exploration inspired by the idea of the Mask1 synth.
// It's meant for the bitwise Norns script.
// A related application in sample chopping
// Can also add wavetable morphing effects

(
// Create buffer and fill it
b = Buffer.alloc(s, 2048); // 2x size for wavetable format
)

(
// Function to process regular buffer then convert to wavetable
~processBitmask = { |numBits=8, mask=255, operation=\zero|
    var size = 1024;  // Regular buffer size
    var segmentSize = size/numBits;
    var signal = Signal.fill(size, { |i|
        sin(2pi * i/size)  // Generate sine wave
    });

    // Process each segment according to mask
    numBits.do({ |i|
        var startIndex = (i * segmentSize).asInteger;
        var endIndex = ((i + 1) * segmentSize).asInteger;

		// TODO: support contiguous region operations (e.g. flipLong flips all contiguous 1 values of bitmask.)
		// TODO take an array of bitmasks and operations, apply in serial
		// FIXME /repeat errors if the 1 bit is set to 1
        if((mask >> i & 1) == 1, {
            startIndex.to(endIndex-1).do({ |j|
                signal[j] = switch(operation,
                    \zero, { 0 },
                    \invert, { signal[j] * -1 },
                    \half, { signal[j] * 0.5 },
                    \double, { signal[j] * 2.0 },
					\repeat, { signal[(j-segmentSize).wrap2(size)] },
                    \fold, { signal[j].fold2(0.5) },
                    { signal[j] }
                );
            });
        });
    });

    // Convert to wavetable format and load into buffer
    b.loadCollection(signal.asWavetable);
};
)

(
// b.sine1([1]); // Fill with basic sine wave
~processBitmask.(8, 2r10001000, \repeat);
b.plot
)


(
// Simple synth to play the wavetable
SynthDef(\bitmaskOsc, { |out=0, freq=440, amp=0.5, gate=1|
    var sig = Osc.ar(b, freq, 0, amp);
    var env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 2);
    Out.ar(out, sig * env ! 2);
}).add;
)

// Test it
Synth(\bitmaskOsc, [freq: 110]);
Server.freeAll


Server.killAll
