% brillem -- a MATLAB interface for brille
% Copyright 2020 Greg Tucker
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>.

function sqw = horace_sqw(obj,qh,qk,ql,en,input_pars,varargin)
% Input:
% ------
%   qh,qk,ql,en Arrays containing points at which to evaluate sqw from the
%               broadened dispersion
%
%   pars        Arguments needed by the function.
%               - Should be a vector of parameters
%                 args = [scale_factor resolution_pars]
%               - The remaining parameters relate the convolution function
%                 defined by the 'resfun' option
%                 (either one or two parameters depending on function type)
%               - The last parameter is a scale factor for the intensity
%
%   kwds       A series of 'keywords' and parameters.
%
%              Some keywords control aspects of this function:
%              'coordtrans' - a matrix to transform the input coordinates
%                             (qh,qk,ql,en) before being sent to the
%                             py.brille.euphonic.BrillEu object's method.
%                             [default: eye(4) % identity]
%
%              Any additional keyword parameters will be passed to SymSim
%              as a py.dict for processing.
%              Notably, one should provide at least
%              'resfun' - which determines the broadening function to
%                         convert S_i(Q(w_i)) into S(Q,E).
%                         This should be a string with one of the following
%                         values:
%                 'sho'   - Simple Harmonic Oscillator linewidth, with its
%                           own (optional) inclusion of the Bose thermal
%                           population factor. resolution_pars are
%                           [FWHM, sample temperature]
%                 'gauss' - gaussian with single fixed (fittable) FWHM
%                 'lor'   - lorentzian with single fixed (fittable) FWHM
%                 'voi'   - Faddeeva-based estimate to a true voigt
%                           function, requiring the FWHM of both the
%                           gaussian and lorentzian functions to be
%                           convoluted. resolution_pars are
%                           [gaussian_FWHM, lorentzian_FWHM]
%                         [default: 'gauss']
%
%              Other keyword-value pairs which are expected by SimPhony are
%              'scale'     - A scale factor, in addition to the one already
%                            required as part of args -- probably should
%                            not be used.
%                            [default: 1]
%              'dw_seed'   - Used in an optional Deby-Waller calculation
%                            [default: ?]
%              'dw_grid'   - Used in an optional Deby-Waller calculation
%                            [default: ?]
%              'calc_bose' - Whether the phonon structure factors should be
%                            corrected for the Bose factor. Note: if the
%                            simple harmonic oscillator broadening function
%                            is selected the *broadened lineshapes* will be
%                            corrected for the Bose factor.
%                            [default: true]
%             'temperature'- The sample temperature used in the Deby-Waller
%                            and Bose factor corrections. For the simple
%                            harmonic oscillator function, the temperature
%                            provided with its parameters will override
%                            this keyword.
%                            [default: 5 K]
%
% Output:
% -------
%   sqw        Array with spectral weight at the Q,E points
%              [ size(sqw) == size(qh) ]
matkeys.names = {'coordtrans'};
matkeys.defaults = {eye(4)};
matkeys.sizes = {[4,4]};
[matkwds, dict] = brillem.readparam(matkeys, varargin{:});

assert(ismatrix(input_pars) && isnumeric(input_pars), 'Numeric matrix input parameters are required')

% chunk the q points:
nQ = numel(qh);
memmult = 3; % Fudge-factor based on NDLT1145 (Win10, 32GB RAM)
pt_per_chunk = double(brillem.chunk_size(obj.pyobj.grid, memmult));
no_chunks = ceil(nQ/pt_per_chunk);
chunk_list = 0:pt_per_chunk:nQ;
if nQ < pt_per_chunk * no_chunks
  chunk_list = [chunk_list nQ];
end

inshape = size(qh);
if size(qh,1) ~= nQ
    qh = qh(:);
    qk = qk(:);
    ql = ql(:);
    en = en(:);
end
% Transforms input coordinates if needed
if sum(sum(abs(matkwds.coordtrans - eye(4)))) > 0
    qc = [qh qk ql en];
    qh = sum(bsxfun(@times, matkwds.coordtrans(1,:), qc),2);
    qk = sum(bsxfun(@times, matkwds.coordtrans(2,:), qc),2);
    ql = sum(bsxfun(@times, matkwds.coordtrans(3,:), qc),2);
    en = sum(bsxfun(@times, matkwds.coordtrans(4,:), qc),2);
    clear qc;
end

if isfield(dict,'scale')
    scale = dict.scale;
else
    scale = 1;
end
if isfield(dict,'temperature')
    temp = dict.temperature;
else
    temp = 5;
end
pars = [];
if isfield(dict,'resfun') && ischar(dict.resfun)
    switch lower(dict.resfun)
        case {'g','gauss','gaussian','l','lor','lorentz','lorentzian'}
            pars = input_pars(1);
            if numel(input_pars) > 1; scale = input_pars(2); end
        case {'v','voi','voigt'}
            pars = input_pars(1:2);
            if numel(input_pars) > 2; scale = input_pars(3); end
        case {'s','sho','simple harmonic oscillator'}
            pars = input_pars(1);
            temp = input_pars(2);
            if numel(args) > 2; scale = input_pars(3); end
    end
end
dict.scale = scale;
dict.temperature = temp;
if ~isempty(pars)
    dict.param = pars;
end

sqw_chunk = cell(1, no_chunks);
% call the inner function on the chunks
wd = 1;
if no_chunks > 1
  fprintf('Evaluate S(Q,W) split into %d chunks:\n',no_chunks);
  nd = floor(log10(no_chunks));
  fmt = sprintf('%%%dd',nd);
  wd = 10*floor(80/(9+nd));
end
for i=1:no_chunks
  if no_chunks > 1
    if mod(i,10)==0
      fprintf(fmt,i/10);
      if mod(i,wd)==0
          fprintf('\n');
      end
    else
      fprintf('.');
    end
  end
  ch = chunk_list(i)+1 : chunk_list(i+1);
  sqw_chunk{i} = horace_sqw_inner(obj, qh(ch), qk(ch), ql(ch), en(ch), dict);
end
if mod(no_chunks, wd) > 0
  fprintf('\n');
end
% combine the chunk results
sqw = cat(1, sqw_chunk{:});
% and reshape the output to match the input
if size(sqw) ~= inshape
  sqw = reshape(sqw, inshape);
end
end % horace_sqw


function sqw = horace_sqw_inner(obj, qh, qk, ql, en, dict)
  Q = brillem.m2p(cat(2, qh, qk, ql)); % (nQ, 3)
  fprintf('%s Call Python object''s method\n',datetime());
  pysqw = obj.pyobj.s_qw(Q, brillem.m2p(en), py.dict(dict)); % (nQ,)
  fprintf('%s Python call finished\n', datetime());
  sqw = permute(brillem.p2m(pysqw),[2,1]); % (1,nQ) -> (nQ, 1)
end % end horace_sqw_inner
