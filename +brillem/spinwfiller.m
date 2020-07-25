function [eigval, eigvec] = spinwfiller(swobj, Qh, Qk, Ql, varargin)

d.names = {'usevectors'};
d.defaults = {false};
[kwds, extras] = brillem.readparam(d, varargin{:});
keys = fieldnames(extras);
vars = cell(numel(keys)*2);
for ik = 1:numel(keys)
    
    vars{2*(ik-1)+1} = keys{ik};
    vars{2*(ik-1)+2} = extras.(keys{ik});
end

hkl = [Qh(:) Qk(:) Ql(:)]';

if kwds.usevectors
    spec = swobj.spinwave(hkl, vars{:}, 'saveV', true, 'sortMode', false);
    if (size(spec.omega, 1) / size(spec.V, 1)) == 3 && (size(spec.V, 3) / size(spec.omega, 2)) == 3
        % Incommensurate
        kmIdx = repmat(sort(repmat([1 2 3],1,size(spec.omega, 2))),1,1);
        eigvec = permute(cat(1, spec.V(:,:,kmIdx==1), spec.V(:,:,kmIdx==2), spec.V(:,:,kmIdx==3)), [3 1 2]);
    else
        eigvec = permute(spec.V, [3 1 2]);
    end
else
    spec = swobj.spinwave(hkl, vars{:}, 'sortMode', false, 'formfact', false);
    eigvec = permute(real(spec.Sab), [4 3 1 2]);
end
eigval = permute(real(spec.omega), [2 1]);
